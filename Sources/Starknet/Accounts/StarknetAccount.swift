import BigInt
import Foundation

public enum StarknetAccountError: Error {
    case invalidResponse
}

public enum CairoVersion: String, Encodable {
    case zero
    case one
}

public class StarknetAccount: StarknetAccountProtocol {
    private let version = Felt.one
    private let cairoVersion: CairoVersion

    private var estimateVersion: Felt {
        Felt(BigUInt(2).power(128).advanced(by: BigInt(version.value)))!
    }

    public let address: Felt

    private let signer: StarknetSignerProtocol
    private let provider: StarknetProviderProtocol

    public init(address: Felt, signer: StarknetSignerProtocol, provider: StarknetProviderProtocol, cairoVersion: CairoVersion) {
        self.address = address
        self.signer = signer
        self.provider = provider
        self.cairoVersion = cairoVersion
    }

    private func makeInvokeTransaction(calldata: StarknetCalldata, signature: StarknetSignature, params: StarknetExecutionParams, forFeeEstimation: Bool = false) -> StarknetInvokeTransactionV1 {
        StarknetInvokeTransactionV1(senderAddress: address, calldata: calldata, signature: signature, maxFee: params.maxFee, nonce: params.nonce, forFeeEstimation: forFeeEstimation)
    }

    private func makeDeployAccountTransaction(classHash: Felt, salt: Felt, calldata: StarknetCalldata, signature: StarknetSignature, params: StarknetExecutionParams) -> StarknetDeployAccountTransactionV1 {
        StarknetDeployAccountTransactionV1(
            signature: signature,
            maxFee: params.maxFee,
            nonce: params.nonce,
            contractAddressSalt: salt,
            constructorCalldata: calldata,
            classHash: classHash
        )
    }

    public func sign(calls: [StarknetCall], params: StarknetExecutionParams, forFeeEstimation: Bool) throws -> StarknetInvokeTransactionV1 {
        let calldata = starknetCallsToExecuteCalldata(calls: calls, cairoVersion: cairoVersion)

        let sequencerTransaction = makeInvokeTransaction(calldata: calldata, signature: [], params: params, forFeeEstimation: forFeeEstimation)

        let hash = StarknetTransactionHashCalculator.computeHash(of: sequencerTransaction, chainId: provider.starknetChainId)

        let signature = try signer.sign(transactionHash: hash)

        return makeInvokeTransaction(calldata: calldata, signature: signature, params: params, forFeeEstimation: forFeeEstimation)
    }

    public func signDeployAccount(classHash: Felt, calldata: StarknetCalldata, salt: Felt, params: StarknetExecutionParams, forFeeEstimation _: Bool) throws -> StarknetDeployAccountTransactionV1 {
        let sequencerTransaction = makeDeployAccountTransaction(classHash: classHash, salt: salt, calldata: calldata, signature: [], params: params)

        let hash = StarknetTransactionHashCalculator.computeHash(of: sequencerTransaction, chainId: provider.starknetChainId)

        let signature = try signer.sign(transactionHash: hash)

        return makeDeployAccountTransaction(classHash: classHash, salt: salt, calldata: calldata, signature: signature, params: params)
    }

    public func execute(calls: [StarknetCall], params: StarknetOptionalExecutionParams) async throws -> StarknetInvokeTransactionResponse {
        var nonce: Felt
        var maxFee: Felt

        if let paramsNonce = params.nonce {
            nonce = paramsNonce
        } else {
            nonce = try await getNonce()
        }

        if let paramsMaxFee = params.maxFee {
            maxFee = paramsMaxFee
        } else {
            let feeEstimate = try await estimateFee(calls: calls, nonce: nonce)
            maxFee = estimatedFeeToMaxFee(feeEstimate.overallFee)
        }

        let signParams = StarknetExecutionParams(nonce: nonce, maxFee: maxFee)
        let transaction = try sign(calls: calls, params: signParams, forFeeEstimation: false)

        let result = try await provider.addInvokeTransaction(transaction)

        return result
    }

    public func estimateFee(calls: [StarknetCall], nonce: Felt) async throws -> StarknetFeeEstimate {
        let signParams = StarknetExecutionParams(nonce: nonce, maxFee: .zero)
        let transaction = try sign(calls: calls, params: signParams, forFeeEstimation: true)

        return try await provider.estimateFee(for: transaction)
    }

    public func estimateDeployAccountFee(classHash: Felt, calldata: StarknetCalldata, salt: Felt, nonce: Felt) async throws -> StarknetFeeEstimate {
        let params = StarknetExecutionParams(nonce: nonce, maxFee: 0)
        let signedTransaction = try signDeployAccount(classHash: classHash, calldata: calldata, salt: salt, params: params, forFeeEstimation: true)

        return try await provider.estimateFee(for: signedTransaction)
    }

    public func sign(typedData: StarknetTypedData) throws -> StarknetSignature {
        try signer.sign(typedData: typedData, accountAddress: address)
    }

    public func verify(signature: StarknetSignature, for typedData: StarknetTypedData) async throws -> Bool {
        let messageHash = try typedData.getMessageHash(accountAddress: address)

        let calldata = [messageHash, Felt(signature.count)!] + signature
        let call = StarknetCall(
            contractAddress: address,
            entrypoint: starknetSelector(from: "isValidSignature"),
            calldata: calldata
        )

        do {
            let result = try await provider.callContract(call)

            guard result.count == 1 else {
                throw StarknetAccountError.invalidResponse
            }

            return result[0] > 0
        } catch let StarknetProviderError.jsonRpcError(code, errorMessage, data) {
            // isValidSignature contract method throws an error, when the signature is incorrect,
            // so we catch it here.
            if errorMessage.contains("Signature"), errorMessage.contains("is invalid") {
                return false
            }

            throw StarknetProviderError.jsonRpcError(code, errorMessage, data)
        }
        // And we want to rethrow all other errors.
    }

    public func getNonce() async throws -> Felt {
        let result = try await provider.getNonce(of: address)

        return result
    }
}
