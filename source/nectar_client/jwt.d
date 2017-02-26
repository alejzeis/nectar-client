module nectar_client.jwt;

import std.string : toStringz, fromStringz;

import derelict.jwt.jwt;

bool verifyJWT(in string jwt, in string key, in jwt_alg_t expectedAlg = JWT_ALG_ES384) 
in {
    assert(DerelictJWT.isLoaded(), "DerelictJWT needs to be loaded before libjwt methods can be called!");
} body {
    jwt_t* ptrJwt;
    const char *tokenPtr = toStringz(jwt);
    const char *keyPtr = toStringz(key);

    // Verify the JWT based on the token and it's algorithm
    if(jwt_decode(&ptrJwt, tokenPtr, keyPtr, cast(int) key.length) != 0) {
        return false;
    }

    // Verification succeeded, but we need to check if the token was using the algorithm we wanted
    // See https://github.com/benmcollins/libjwt/issues/33 for more information.
    if(jwt_get_alg(ptrJwt) != expectedAlg) {
        return false;
    }

    jwt_free(ptrJwt);

    return true;
}

string constructJWT(in string json, in string key, in jwt_alg_t algorithm = JWT_ALG_ES384) 
in {
    assert(DerelictJWT.isLoaded(), "DerelictJWT needs to be loaded before libjwt methods can be called!");
} body {
    jwt_t* ptrJwt;
    jwt_new(&ptrJwt);

    jwt_set_alg(ptrJwt, algorithm, toStringz(key), cast(int) key.length); // Set the token algorithm to the one we want

    jwt_add_grants_json(ptrJwt, toStringz(json)); // Set the payload to the json

    auto encoded = fromStringz(jwt_encode_str(ptrJwt));

    jwt_free(ptrJwt);

    return cast(string) encoded;
}