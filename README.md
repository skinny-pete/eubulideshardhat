# Eubulides ⏳

Eubulides is a project offering fixed yield positions on user deposits into Uniswap V3. Users will be quoted a fixed yield as a percentage, claimable at the end of their stake duration. This is a Hardhat project, and contains PoC contracts and some basic unit tests

## Features 🛠️

- **Historical Yield Positions:** Users can deposit funds and receive fixed yield quote based on historical yield rates.
- **Autocompounding Yield** Automatic reinvestment of fees on user deposits
- **Liquidity Management** Frequently redeploys liquidity to optimise fee collection by staying in the active tick range.
- **Fungible Liquidity** Share tokens are ERC20-compliant and are not tied to the non-fungible user position, so liquidity can be used elsewhere while users earn.

## Setup 🚀
Note that the code is on 'master' branch *not* main

1. Install the required packages:
   ```bash
   npm install --legacy-peer-deps
   ```
   Due to the nature of a hackathon we had to hack dependencies a little to get everything running - this will be resolved, and contracts updated to use compiler 8+

## Tests
```bash
npx hardhat test
```

## WIP ##
Not all features are implemented at this stage, these are the areas of ongoing development:
- Autocompounding - Redeploying liquidity requires careful swapping to a new ratio, which proved too complex for this hackathon but is partially implemented already
- ERC-4626 - The core contract will be upgraded to use ERC4626 (Tokenized Vaults)
- Quotes/Fixed yield settlement - Although most of the internal tools required are implemented, there wasn't time to connect this together to allow users to get their fixed yield, but we hope the code in this repository shows how it will be possible through yield checkpointing
