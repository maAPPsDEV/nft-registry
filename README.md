# NFT Registry - A meta transactional Non Fungible Token Registry

## Description

The project is to implement a registry using an ERC1155 or ERC721 template from OpenZeppelin.

The registry should allow for the following:

- Allow user to register [IPFS hash](https://docs.ipfs.io/concepts/hashing/) of some underlying document or folder as a new NFT.
- Allow user to register a βserviceβ that has a name and points to a collection of NFTs and a single address of an EOA.
- Has an execute function similar to the one in [ERC725X](https://eips.ethereum.org/EIPS/eip-725) plus an additional argument which is the βserviceβ name. This function checks that the tx it receives is signed by the EOA which is registered for the service and then makes the contract to contract call specified.

## Configuration

### Install Truffle cli

_Skip if you have already installed._

```
npm install -g truffle
```

### Install Dependencies

```
npm install
```

## Test!π₯

### Run Tests

Launch Ganache then run:

```
npm run test
```

or test in truffle console

```
truffle(develop)> test
Using network 'develop'.


Compiling your contracts...
===========================
> Everything is up to date, there is nothing to compile.



  Contract: Registry
    Metadata
      β should get name (172ms)
      β should get symbol (136ms)
    Meta-transaction
      β should verify signature (405ms)
      β should revert when an invalid signer provided (681ms)
    Service
      register
        β should register a service (378ms)
        β should revert if the service exists already (841ms)
      unregister
        β should unregister a service (762ms)
        β should revert if the service doesn't exist (483ms)
        β should revert when the signer has no permission (817ms)
    Token
      register
        β should register a token (571ms)
        β should register a token and add to a service (1136ms)
        β should revert if the given service doesn't exist (406ms)
      unregister
        β should unregister a token (1001ms)
        β should revert if the token doesn't exist (564ms)
        β should revert when the signer has no permission (735ms)
    Token-Service Relationship
      β should use a token for a service (1326ms)
      β should revert if the service doesn't exist (807ms)
      β should unuse a token for a service (1809ms)
      β should revert if the token doesn't exist (1040ms)
    execute
      β should revert if the signer has no permission (1009ms)
      β should revert if the unsupported operation requested (954ms)
      β should external call (1067ms)


  22 passing (31s)

```
