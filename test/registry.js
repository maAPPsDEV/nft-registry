const Registry = artifacts.require("Registry");
const { expect } = require("chai");
const { BN, expectEvent } = require("@openzeppelin/test-helpers");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
async function sign(nonce, signer, ...data) {
  console.log("signed data", data);
  let hash = web3.utils.soliditySha3(...data); // remove 0x prefix
  console.log("hash1", hash, nonce.toString());
  console.log("hash11", web3.utils.soliditySha3({ t: "string", v: "service1" }));
  hash = web3.utils.soliditySha3({ t: "uint256", v: nonce }, { t: "bytes32", v: hash });
  console.log("hash2", hash);
  // hash = web3.utils.soliditySha3({t: "string", v: "\x19Ethereum Signed Message:\n32"}, {t: "bytes32", v: hash});
  // console.log('hash3', hash)
  return await web3.eth.sign(hash, signer);
}

contract("Registry", function ([_owner, _signer]) {
  let registry;
  let signer;
  const password = "password";
  beforeEach(async function () {
    registry = await Registry.deployed();
    // signer = await web3.eth.personal.newAccount(password);
    // console.log("new account", signer)
  });

  context("Meta", function () {
    it("should get name", async function () {
      expect(await registry.name()).to.be.equal("Valory Registry");
    });

    it("should get symbol", async function () {
      expect(await registry.symbol()).to.be.equal("VRT");
    });
  });

  context("Service", function () {
    it("should register a service", async function () {
      const serviceName = "service1";
      const signature = await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceName });
      console.log("signature", signature);
      const result = await registry.registerService(serviceName, signature, _signer);
      console.log("result", result);
      expect(result.receipt.status).to.be.equal(true);
      expectEvent(result.receipt, "ServiceRegistered", {
        name: serviceName,
        owner: _signer,
      });
    });
  });
});
