derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
# fx68k internal paths: two-cycle setup
set_multicycle_path -setup -start -from [get_keepers {*fx68k:*|Ir[*]}] -to [get_keepers {*fx68k:*|microAddr[*]}] 2
set_multicycle_path -hold -start -from [get_keepers {*fx68k:*|Ir[*]}] -to [get_keepers {*fx68k:*|microAddr[*]}] 1
set_multicycle_path -setup -start -from [get_keepers {*fx68k:*|Ir[*]}] -to [get_keepers {*fx68k:*|nanoAddr[*]}] 2
set_multicycle_path -hold -start -from [get_keepers {*fx68k:*|Ir[*]}] -to [get_keepers {*fx68k:*|nanoAddr[*]}] 1

set_multicycle_path -setup -start -from [get_keepers {*|nanoLatch[*]}] -to [get_keepers {*|excUnit|alu|pswCcr[*]}] 2
set_multicycle_path -hold -start -from [get_keepers {*|nanoLatch[*]}] -to [get_keepers {*|excUnit|alu|pswCcr[*]}] 1
set_multicycle_path -setup -start -from [get_keepers {*|excUnit|alu|oper[*]}] -to [get_keepers {*|excUnit|alu|pswCcr[*]}] 2
set_multicycle_path -hold -start -from [get_keepers {*|excUnit|alu|oper[*]}] -to [get_keepers {*|excUnit|alu|pswCcr[*]}] 1

# T80pa internal paths: two-cycle setup
set_multicycle_path -setup -start -from [get_keepers {*|T80pa:u_cpu|*}] -to [get_keepers {*|T80pa:u_cpu|*}] 2
set_multicycle_path -hold -start -from [get_keepers {*|T80pa:u_cpu|*}] -to [get_keepers {*|T80pa:u_cpu|*}] 1
