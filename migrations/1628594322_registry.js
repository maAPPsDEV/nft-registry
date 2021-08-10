const Registry = artifacts.require("Registry");

module.exports = function (_deployer, _, [_owner]) {
  // Use deployer to state migration tasks.
  _deployer.deploy(Registry, { from: _owner });
};
