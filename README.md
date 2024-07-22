# 🚀 Polygon Multi-threshold Smart Contract Upgrades Plugin for Aragon OSx

Welcome to the Polygon Multi-threshold Smart Contract Upgrades Plugin for Aragon OSx! This plugin enhances the flexibility and security of your Aragon DAOs by introducing a multi-threshold approval mechanism for standard and emergency proposals.

## 🎯 Features

- **Dual Proposal Types**: Standard and Emergency proposals with different thresholds.
- **Configurable Thresholds**: Set distinct approval requirements for standard and emergency proposals.
- **Delayed Confirmation**: Standard proposals include an offchain voting period before final execution.
- **Customizable Execution**: Execute proposals by anyone or only by members.

## 🛠️ Usage

### 📝 Standard Proposals

1. **Creation**:
   - Standard proposals are created by any member.
   - Requires an initial set of member approvals (configurable).

2. **Delay Period**:
   - After initial approvals, a delay period begins.
   - Offchain voting can occur during this period.

3. **Confirmation**:
   - Post delay, additional member approvals equal to the initial threshold are needed.

4. **Execution**:
   - Can be executed by anyone or only by members (set in the config).
   - Execution rights and thresholds are configurable.

### 🚨 Emergency Proposals

1. **Creation**:
   - Emergency proposals are created when immediate action is needed.
   - Requires a higher threshold of member approvals (configurable).

2. **Immediate Execution**:
   - Once the higher approval threshold is met, the proposal can be executed immediately.
   - Execution rights are configurable to be either public or restricted to members.

## ⚙️ Configuration

### Setting Thresholds

- **Standard Proposal Threshold**: Number of approvals required to start the delay period and to confirm the execution.
- **Emergency Proposal Threshold**: Number of approvals required for immediate execution.


## 📈 Proposal Flow

### Standard Proposal Flow

1. **Proposal Creation** 📝
2. **Initial Approval** ✅
3. **Delay Period** ⏳
4. **Final Confirmation** ✅
5. **Execution** 🚀

### Emergency Proposal Flow

1. **Proposal Creation** 📝
2. **High Threshold Approval** 🚨
3. **Immediate Execution** 🚀

### Testing
Run tests to ensure your plugins are working correctly:

``` bash
forge test
```

Deployment
Deploy your plugin to a network:
```bash
source .env
forge script script/Deploy.s.sol:Deploy --broadcast --rpc-url <RPC_URL> 
```

### License 📄
This project is licensed under AGPL-3.0-or-later.

### 🤝 Contributing

Feel free to open issues and submit pull requests. We welcome contributions that enhance the functionality and usability of this plugin.

### 📬 Contact

For questions and support, reach out to us on our [Twitter](https://x.com/aragonproject) or [Discord](https://discord.gg/aragon) or directly in the issues section in this repo.

---

Thank you for using the Polygon Multi-threshold Smart Contract Upgrades Plugin for Aragon OSx! Your feedback and contributions are highly valued. Happy upgrading! 🚀
