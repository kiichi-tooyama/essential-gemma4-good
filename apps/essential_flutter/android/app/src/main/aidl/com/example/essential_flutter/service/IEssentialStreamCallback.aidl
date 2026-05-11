package com.example.essential_flutter.service;

oneway interface IEssentialStreamCallback {
    void onChunk(String requestId, String chunkJson);
    void onComplete(String requestId, String responseJson);
    void onError(String requestId, String errorCode, String message);
}