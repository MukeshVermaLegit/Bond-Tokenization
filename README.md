# Bond-Tokenization

A Proof of Concept for a tokenized U.S. Treasury-style bond built in Solidity with Foundry.

##  Features
- ERC-20 based BondToken
- Fixed face value & coupon rate
- Interest accrues monthly
- Claim interest anytime before maturity
- Redeem principal + final interest at maturity
- Includes MockUSDC for deposits/payouts
- Fully tested with Foundry

##  Quick Start
```bash
foundryup
git clone https://github.com/MukeshVermaLegit/Bond-Tokenization.git
cd Bond-Tokenization
forge install
forge build
forge test
