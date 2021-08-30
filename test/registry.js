const Registry = artifacts.require("Registry");
const ExternalMock = artifacts.require("ExternalMock");

const { expect } = require("chai");
const { BN, expectEvent, expectRevert } = require("@openzeppelin/test-helpers");
const { web3 } = require("@openzeppelin/test-helpers/src/setup");
const { ZERO_ADDRESS } = require("@openzeppelin/test-helpers/src/constants");

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
async function sign(nonce, signer, ...data) {
  let hash = web3.utils.soliditySha3(...data);
  hash = web3.utils.soliditySha3({ t: "uint256", v: nonce }, { t: "bytes32", v: hash });
  return await web3.eth.sign(hash, signer);
}

function encodeMockFunctionCall(value) {
  return web3.eth.abi.encodeFunctionCall(
    {
      name: "foo",
      type: "function",
      inputs: [
        {
          type: "string",
          name: "value",
        },
      ],
    },
    [value],
  );
}

contract("Registry", function ([_owner, _signer]) {
  const serviceNames = ["service1", "service2"];
  const tokenIds = [web3.utils.randomHex(32), web3.utils.randomHex(32), web3.utils.randomHex(32)];
  let registry;
  let mock;

  beforeEach(async function () {
    registry = await Registry.new();
    mock = await ExternalMock.new();
  });

  context("Metadata", function () {
    it("should get name", async function () {
      expect(await registry.name()).to.be.equal("Valory Registry");
    });

    it("should get symbol", async function () {
      expect(await registry.symbol()).to.be.equal("VRT");
    });
  });

  context("Meta-transaction", function () {
    it("should verify signature", async function () {
      const result = await registry.registerService(
        serviceNames[0],
        await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
        _signer,
      );
      expect(result.receipt.status).to.be.equal(true);
    });

    it("should revert when an invalid signer provided", async function () {
      await expectRevert(
        registry.registerService(
          serviceNames[0],
          await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
          _owner,
        ),
        "VRT: Invalid signer",
      );
    });
  });

  context("Service", function () {
    context("register", function () {
      it("should register a service", async function () {
        const result = await registry.registerService(
          serviceNames[0],
          await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
          _signer,
        );
        expect(result.receipt.status).to.be.equal(true);
        expectEvent(result, "ServiceRegistered", {
          name: serviceNames[0],
          owner: _signer,
        });
      });

      it("should revert if the service exists already", async function () {
        await registry.registerService(
          serviceNames[0],
          await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
          _signer,
        );
        await expectRevert(
          registry.registerService(
            serviceNames[0],
            await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
            _signer,
          ),
          "VRT: Service already exist",
        );
      });
    });

    context("unregister", function () {
      it("should unregister a service", async function () {
        await registry.registerService(
          serviceNames[0],
          await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
          _signer,
        );
        const result = await registry.unregisterService(
          serviceNames[0],
          await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
          _signer,
        );
        expect(result.receipt.status).to.be.equal(true);
        expectEvent(result, "ServiceUnregistered", {
          name: serviceNames[0],
          owner: _signer,
        });
      });

      it("should revert if the service doesn't exist", async function () {
        await expectRevert(
          registry.unregisterService(
            serviceNames[0],
            await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
            _signer,
          ),
          "VRT: Service not found",
        );
      });

      it("should revert when the signer has no permission", async function () {
        await registry.registerService(
          serviceNames[0],
          await sign(await registry.nonces(_owner), _owner, { t: "string", v: serviceNames[0] }),
          _owner,
        );
        await expectRevert(
          registry.unregisterService(
            serviceNames[0],
            await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
            _signer,
          ),
          "VRT: No permission",
        );
      });
    });
  });

  context("Token", function () {
    context("register", function () {
      it("should register a token", async function () {
        const result = await registry.registerToken(
          _signer,
          tokenIds[0],
          await sign(await registry.nonces(_signer), _signer, { t: "address", v: _signer }, { t: "bytes32", v: tokenIds[0] }),
          _signer,
        );
        expect(result.receipt.status).to.be.equal(true);
        expectEvent(result, "Transfer", {
          from: ZERO_ADDRESS,
          to: _signer,
          tokenId: web3.utils.toBN(tokenIds[0]),
        });
        expect(await registry.ownerOf(tokenIds[0])).to.be.equal(_signer);
      });

      it("should register a token and add to a service", async function () {
        await registry.registerService(
          serviceNames[0],
          await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
          _signer,
        );
        const result = await registry.registerToken(
          _signer,
          tokenIds[0],
          serviceNames[0],
          await sign(
            await registry.nonces(_signer),
            _signer,
            { t: "address", v: _signer },
            { t: "bytes32", v: tokenIds[0] },
            { t: "string", v: serviceNames[0] },
          ),
          _signer,
        );
        expect(result.receipt.status).to.be.equal(true);
        expectEvent(result, "TokenUsed", {
          tokenId: tokenIds[0],
          serviceName: serviceNames[0],
        });
        expect(await registry.ownerOf(tokenIds[0])).to.be.equal(_signer);
      });

      it("should revert if the given service doesn't exist", async function () {
        await expectRevert(
          registry.registerToken(
            _signer,
            tokenIds[0],
            serviceNames[0],
            await sign(
              await registry.nonces(_signer),
              _signer,
              { t: "address", v: _signer },
              { t: "bytes32", v: tokenIds[0] },
              { t: "string", v: serviceNames[0] },
            ),
            _signer,
          ),
          "VRT: Service not found",
        );
      });
    });

    context("unregister", function () {
      it("should unregister a token", async function () {
        await registry.registerToken(
          _signer,
          tokenIds[0],
          await sign(await registry.nonces(_signer), _signer, { t: "address", v: _signer }, { t: "bytes32", v: tokenIds[0] }),
          _signer,
        );
        const result = await registry.unregisterToken(
          tokenIds[0],
          await sign(await registry.nonces(_signer), _signer, { t: "bytes32", v: tokenIds[0] }),
          _signer,
        );
        expect(result.receipt.status).to.be.equal(true);
        expectEvent(result, "Transfer", {
          from: _signer,
          to: ZERO_ADDRESS,
          tokenId: web3.utils.toBN(tokenIds[0]),
        });
        await expectRevert(registry.ownerOf(tokenIds[0]), "ERC721: owner query for nonexistent token");
      });

      it("should revert if the token doesn't exist", async function () {
        await expectRevert(
          registry.unregisterToken(tokenIds[0], await sign(await registry.nonces(_signer), _signer, { t: "bytes32", v: tokenIds[0] }), _signer),
          "VRT: Token not found",
        );
      });

      it("should revert when the signer has no permission", async function () {
        await registry.registerToken(
          _owner,
          tokenIds[0],
          await sign(await registry.nonces(_owner), _owner, { t: "address", v: _owner }, { t: "bytes32", v: tokenIds[0] }),
          _owner,
        );
        await expectRevert(
          registry.unregisterToken(tokenIds[0], await sign(await registry.nonces(_signer), _signer, { t: "bytes32", v: tokenIds[0] }), _signer),
          "VRT: No permission",
        );
      });
    });
  });

  context("Token-Service Relationship", function () {
    it("should use a token for a service", async function () {
      await registry.registerService(
        serviceNames[0],
        await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
        _signer,
      );
      await registry.registerToken(
        _signer,
        tokenIds[0],
        await sign(await registry.nonces(_signer), _signer, { t: "address", v: _signer }, { t: "bytes32", v: tokenIds[0] }),
        _signer,
      );
      const result = await registry.useToken(
        tokenIds[0],
        serviceNames[0],
        await sign(await registry.nonces(_signer), _signer, { t: "bytes32", v: tokenIds[0] }, { t: "string", v: serviceNames[0] }),
        _signer,
      );
      expect(result.receipt.status).to.be.equal(true);
      expectEvent(result, "TokenUsed", {
        tokenId: tokenIds[0],
        serviceName: serviceNames[0],
      });
    });

    it("should revert if the service doesn't exist", async function () {
      await registry.registerToken(
        _signer,
        tokenIds[0],
        await sign(await registry.nonces(_signer), _signer, { t: "address", v: _signer }, { t: "bytes32", v: tokenIds[0] }),
        _signer,
      );
      await expectRevert(
        registry.useToken(
          tokenIds[0],
          serviceNames[0],
          await sign(await registry.nonces(_signer), _signer, { t: "bytes32", v: tokenIds[0] }, { t: "string", v: serviceNames[0] }),
          _signer,
        ),
        "VRT: Service not found",
      );
    });

    it("should unuse a token for a service", async function () {
      await registry.registerService(
        serviceNames[0],
        await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
        _signer,
      );
      await registry.registerToken(
        _signer,
        tokenIds[0],
        await sign(await registry.nonces(_signer), _signer, { t: "address", v: _signer }, { t: "bytes32", v: tokenIds[0] }),
        _signer,
      );
      await registry.useToken(
        tokenIds[0],
        serviceNames[0],
        await sign(await registry.nonces(_signer), _signer, { t: "bytes32", v: tokenIds[0] }, { t: "string", v: serviceNames[0] }),
        _signer,
      );
      const result = await registry.unuseToken(
        tokenIds[0],
        serviceNames[0],
        await sign(await registry.nonces(_signer), _signer, { t: "bytes32", v: tokenIds[0] }, { t: "string", v: serviceNames[0] }),
        _signer,
      );
      expect(result.receipt.status).to.be.equal(true);
      expectEvent(result, "TokenUnused", {
        tokenId: tokenIds[0],
        serviceName: serviceNames[0],
      });
    });

    it("should revert if the token doesn't exist", async function () {
      await registry.registerService(
        serviceNames[0],
        await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
        _signer,
      );
      await expectRevert(
        registry.unuseToken(
          tokenIds[0],
          serviceNames[0],
          await sign(await registry.nonces(_signer), _signer, { t: "bytes32", v: tokenIds[0] }, { t: "string", v: serviceNames[0] }),
          _signer,
        ),
        "VRT: Token not found",
      );
    });
  });

  const OPERATION_CALL = 0;
  const OPERATION_DELEGATECALL = 1;
  context("execute", function () {
    it("should revert if the signer has no permission", async function () {
      await registry.registerService(
        serviceNames[0],
        await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
        _signer,
      );
      const data = encodeMockFunctionCall("😂");
      await expectRevert(
        registry.execute(
          OPERATION_CALL,
          mock.address,
          0,
          data,
          serviceNames[0],
          await sign(
            await registry.nonces(_owner),
            _owner,
            { t: "uint256", v: OPERATION_CALL },
            { t: "address", v: mock.address },
            { t: "uint256", v: 0 },
            { t: "bytes", v: data },
            { t: "string", v: serviceNames[0] },
          ),
          _owner,
        ),
        "VRT: No permission",
      );
    });

    it("should revert if the unsupported operation requested", async function () {
      await registry.registerService(
        serviceNames[0],
        await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
        _signer,
      );
      const data = encodeMockFunctionCall("😂");
      await expectRevert(
        registry.execute(
          OPERATION_DELEGATECALL,
          mock.address,
          0,
          data,
          serviceNames[0],
          await sign(
            await registry.nonces(_signer),
            _signer,
            { t: "uint256", v: OPERATION_DELEGATECALL },
            { t: "address", v: mock.address },
            { t: "uint256", v: 0 },
            { t: "bytes", v: data },
            { t: "string", v: serviceNames[0] },
          ),
          _signer,
        ),
        "VRT: Unsupported operation",
      );
    });

    it("should external call", async function () {
      await registry.registerService(
        serviceNames[0],
        await sign(await registry.nonces(_signer), _signer, { t: "string", v: serviceNames[0] }),
        _signer,
      );
      const data = encodeMockFunctionCall("😂");
      const value = web3.utils.toWei("1", "wei");
      const result = await registry.execute(
        OPERATION_CALL,
        mock.address,
        value,
        data,
        serviceNames[0],
        await sign(
          await registry.nonces(_signer),
          _signer,
          { t: "uint256", v: OPERATION_CALL },
          { t: "address", v: mock.address },
          { t: "uint256", v: value },
          { t: "bytes", v: data },
          { t: "string", v: serviceNames[0] },
        ),
        _signer,
        { value },
      );
      expect(result.receipt.status).to.be.equal(true);
      expect(await mock.bar()).to.be.equal("😂");
      expect(await web3.eth.getBalance(mock.address)).to.be.bignumber.equal(value);
    });
  });
});
