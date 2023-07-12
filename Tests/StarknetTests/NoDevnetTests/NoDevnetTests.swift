import XCTest

@testable import Starknet

final class NoDevnetTests: XCTestCase {
    var provider: StarknetProviderProtocol!

    override func setUp() async throws {
        try await super.setUp()
        provider = StarknetProvider(starknetChainId: .testnet, url: "https://api.hydrogen.argent47.net/v1/starknet/goerli/rpc/v0.3")!
    }

    func testEstimateMessageFeeCall() async throws {
        let message = StarknetCall(
            contractAddress: Felt(fromHex: "0x073314940630fd6dcda0d772d4c972c4e0a9946bef9dabf4ef84eda8ef542b82")!, //  L2 Bridge address
            entrypoint: starknetSelector(from: "handle_deposit"),
            calldata: [
                "0x05576eb79c02935cc5a7697bcc9c411b6924b54c92735d1e2883dc22035330df", // l2 recipient address
                "0x2386f26fc10000", // , amount to deposit
                "0x0",
            ]
        )

        do {
            let result = try await provider.estimateMessageFee(message, senderAddress: Felt("0xc3511006c04ef1d78af4c8e0e74ec18a6e64ff9e"))

            XCTAssertGreaterThan(result.gasPrice, 1)
            XCTAssertGreaterThan(result.gasConsumed, 1)
            XCTAssertGreaterThan(result.overallFee, 1)
        } catch let e {
            print(e)
            throw e
        }
    }
}
