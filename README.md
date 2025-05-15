#  Rebase Token
1. Protocol that allows user to deposit into a vault and in return recieve rebase tokens that represent their underlying balance

2. Rebase token - balanceOf function is dynamic to show the changing balance over time
    - Balance increases linearly with time
    - mint tokens to our users every time they perform an action (minting,burning,transfering,bridging)

3. Interest rate 
    - Individualy set the insterest rate of each user based on global interest rate of the protocol at the time the user deposits into the vault.
    - This global interest rate can only decrease to incetivise/reward early adopters.

4. Known feature/issue - Depositing updates the interest rate, reducing it, which may lead people to using multiple wallets for depositing multiple times.
