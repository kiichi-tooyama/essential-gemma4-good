package com.example.essential_flutter.service;

import com.example.essential_flutter.service.IEssentialStreamCallback;

interface IEssentialService {
    String listModels();
    String listAdapters(String callerPackage, String modelId);
    String runInference(String requestJson);
    void streamInference(String requestJson, IEssentialStreamCallback callback);
    boolean attachAdapter(String sessionId, String adapterId, String callerPackage);
    boolean detachAdapter(String sessionId, String callerPackage);
    boolean cancel(String requestId);
}