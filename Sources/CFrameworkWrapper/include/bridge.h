#ifndef bridge_h
#define bridge_h

#ifdef __OBJC__

#if __has_include(<libcrypto_c_exports/pedersen_hash.h>)
#import <libcrypto_c_exports/pedersen_hash.h>
#import <libcrypto_c_exports/ecdsa.h>
#else
#import "pedersen_hash.h"
#import "ecdsa.h"
#endif

#if __has_include(<libposeidon/poseidon.h>)
#import <libposeidon/poseidon.h>
#else
#import "poseidon.h"
#endif

#import "crypto-rs.h"

#endif

#include <stdio.h>

#endif /* bridge_h */
