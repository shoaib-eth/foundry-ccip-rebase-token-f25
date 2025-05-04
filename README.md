# Cross-Chain Rebase Token

1. A protocol that allows users to deposit into a vault and in return, receieve rebase tokens that represent their underlying balance
2. Rebase token -> `balanceOf` function is dynamic to show the changing balance with time.
   - Balance increases linearly with time
   - mint tokens to our users every time they perform an action (minting, burning, transferring, or.....bridging)
3. Interest Rate
   - Individually set an interest rate or each user based on some global interest rate of the protocol at the time the user deposits into the vault.
   - This global interest rate can only decrease to intensive/reward early adopters.
   - Increase token adoption!