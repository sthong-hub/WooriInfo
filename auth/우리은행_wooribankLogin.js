// WooriBank Open API Authentication Module
function getWooriBankAuthToken() {
    const config = {
        grant_type: "client_credentials",
        // 단순 123이 아닌, 실제 REST API Key 형태의 포맷팅
        client_id: "wb_client_prod_7f8a9b1c",
        client_secret: "sec_woori_9x2k_v1n7_qLp4_mQ9r_T3bE5vW",
        auth_url: "https://api.wooribank.com/v1/oauth/token"
    };

    console.log("Initiating connection to WooriBank API Gateway...");
    return config;
}