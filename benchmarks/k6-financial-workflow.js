import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:3000";
const API_KEY = __ENV.API_KEY || "settleflow_dev_key_change_me";
const SCENARIO = __ENV.SCENARIO || "smoke";

const scenarioOptions = {
  smoke: {
    stages: [
      { duration: "5s", target: 1 },
      { duration: "20s", target: 1 },
      { duration: "5s", target: 0 }
    ]
  },
  load: {
    stages: [
      { duration: "1m", target: 10 },
      { duration: "3m", target: 10 },
      { duration: "1m", target: 0 }
    ]
  },
  stress: {
    stages: [
      { duration: "1m", target: 20 },
      { duration: "2m", target: 40 },
      { duration: "1m", target: 0 }
    ]
  },
  spike: {
    stages: [
      { duration: "15s", target: 50 },
      { duration: "45s", target: 50 },
      { duration: "30s", target: 0 }
    ]
  }
};

export const options = {
  scenarios: {
    workflow: {
      executor: "ramping-vus",
      gracefulRampDown: "10s",
      ...(scenarioOptions[SCENARIO] || scenarioOptions.smoke)
    }
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<500", "p(99)<1000"]
  }
};

function headers(idempotencyKey) {
  return {
    headers: {
      "X-Api-Key": API_KEY,
      "X-Correlation-ID": `k6-${__VU}-${__ITER}`,
      "Idempotency-Key": idempotencyKey,
      "Content-Type": "application/json",
      Accept: "application/json"
    }
  };
}

function postJson(path, body, idempotencyKey) {
  return http.post(`${BASE_URL}${path}`, JSON.stringify(body), headers(idempotencyKey));
}

export default function () {
  const suffix = `${__VU}-${__ITER}-${Date.now()}`;

  const customer = postJson(
    "/v1/customers",
    {
      external_id: `k6-customer-${suffix}`,
      legal_name: "K6 Customer",
      document_kind: "cpf",
      document_number: `${__VU}${__ITER}`.padStart(11, "0")
    },
    `k6-customer-${suffix}`
  );
  check(customer, { "customer created": (response) => response.status === 201 });
  const customerId = customer.json("data.id");

  const wallet = postJson(
    "/v1/wallets",
    {
      customer_id: customerId,
      external_id: `k6-wallet-${suffix}`
    },
    `k6-wallet-${suffix}`
  );
  check(wallet, { "wallet created": (response) => response.status === 201 });
  const walletId = wallet.json("data.id");

  const funding = postJson(
    "/v1/fundings",
    {
      wallet_id: walletId,
      external_id: `k6-funding-${suffix}`,
      amount_cents: 10000
    },
    `k6-funding-${suffix}`
  );
  check(funding, { "funding posted": (response) => response.status === 201 });

  const pix = postJson(
    "/v1/pix_payments",
    {
      wallet_id: walletId,
      external_id: `k6-pix-${suffix}`,
      pix_key: `receiver-${suffix}@example.com`,
      receiver_name: "K6 Receiver",
      amount_cents: 1000
    },
    `k6-pix-${suffix}`
  );
  check(pix, { "pix accepted": (response) => response.status === 201 });

  const balance = http.get(`${BASE_URL}/v1/wallets/${walletId}/balance`, {
    headers: {
      "X-Api-Key": API_KEY,
      Accept: "application/json"
    }
  });
  check(balance, { "balance readable": (response) => response.status === 200 });
  sleep(1);
}
