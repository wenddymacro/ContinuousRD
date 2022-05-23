cd ~/Documents/repos/ContinuousRD
clear all
set more off
set matsize 8100
set maxvar 30000

do inst/QLATE_bc_se.ado

insheet using data/sim_data.csv, clear case

global minq=0.1
global maxq=0.5
global grid=0.1
global qnum = 0
forvalues q=$minq($grid)$maxq {
	global qnum=$qnum+1
}
disp "$qnum"


//Gen scalars//
quiet sum R
global n=r(N)	
scalar sd_R=r(sd)
quiet sum R if R>=0
scalar n_plus=r(N)
quiet sum R if R<0
scalar n_minus=r(N)	
quiet sum T
scalar sd_T=r(sd)	

// Use the optimal bandwidth generated by RD_conT_OptimalBW_6.do (c=4.5) //
// For tau_u, the mean AMSE optimal bandwidth across quantiles for R is 1220.62 and for T is 0.5664//
// For pi, the AMSE optimal bandwidth is the following//
global h_RPi = 2.2288
global h_TPi = 1.0049

//rho_0 is the ratio of the optimal main bandwidth to the preliminary bandwidth used to estimate the trimming thresholds//
global rho_0=4/3

//rho_1 is the ratio of the optimal main bandwidth to the bandwidth used to estimate biases and variances// 
global c = 4.5
global rho_1= $h_RPi/($c*$n^(-1/8)*sd_R)		

//h_R and h_T are the bandwidths for the main estimation//
global h_R=$h_RPi
global h_T=$h_TPi

//h_R0 is the preliminary bandwidth for generating the triming parameter//
global h_R0=$h_R/$rho_0

//h_R1 and h_T1 the bandwidths for estimating the biases and variances (h/b) //
global h_R1=$h_R/$rho_1
global h_T1=$h_R1*sd_T/sd_R

/* disp "h_R: $h_R"
disp "h_R0: $h_R0"
disp "h_R1: $h_R1"
disp "h_T: $h_T"
disp "h_T1: $h_T1" */

//use uniform kernel//
gen kern_R0=0.5
replace kern_R0=0 if abs(R)>$h_R0	
gen kern_R=0.5
replace kern_R=0 if abs(R)>$h_R	
quiet gen kern_R1=0.5
replace kern_R1=0 if abs(R)>$h_R1	

//generate trimming threshold//
mat trim=J($qnum,1,.)
local r=0
forvalues q=$minq($grid)$maxq {
	local r=`r'+1
	quiet qreg T R Z ZR  [iweight=kern_R0], quantile(`q') vce(robust)
	mat trim[`r',1]=_se[Z]*1.96
}

//Silverman rule-of-thumb bandwidth for a unifrom kernel for density estimation//
global h_fR = 1.843*$n^(-0.2)*sd_R   
gen kern_fR=0.5
replace kern_fR=0 if abs(R)>$h_fR	
quiet sum kern_fR
global fR = r(mean)/$h_fR

//Estimate the density of R right above r0//
//Silverman rule-of-thumb bandwidth for a unifrom kernel//
global h_fplus = 0.7344*n_plus^(-1/6)   
quiet replace kern_fR=0.5
quiet replace kern_fR=0 if abs(R)> ($h_fplus*sd_R)	
quiet sum kern_fR if Z == 1
scalar fRplus = r(mean)/($h_fplus*sd_R)

//Estimate the density of R right below r0//
//Silverman rule-of-thumb bandwidth for a unifrom kernel//		
global h_fminus = 0.7344*n_minus^(-1/6)   
quiet replace kern_fR=0.5
quiet replace kern_fR=0 if abs(R)>$h_fminus*sd_R
quiet sum kern_fR if Z == 0
scalar fRminus = r(mean)/($h_fminus*sd_R)


tempname qte qlist tau_u tau_u_bc biasT_plus biasT_minus dmdt_plus dmdt_minus biasRTau_u biasTTau_u BR2 BT2 c 
tempname mi fTRplus fTRminus ifT_Rplus ifT_Rminus sigma2plus sigma2minus SEtau SEtau_bc Vtau qplus qminus
tempname biasRPi_u w_sum w_sum0 pi0 pi biasPi_u1 biasRPi_u2 biasTPi_u2 biasTPi_u biasRPi0 biasRPi biasTPi0 biasTPi pi_bc
tempname sigma2p sigma2m Ap Am sigma2A L1_plus L1_minus SEpi_bcA
tempvar Y2i
local sigma2p=0
local sigma2m=0
mat `qte'=J($qnum,1,.)	
mat `qplus'=J($qnum,1,.)	
mat `qminus'=J($qnum,1,.)	
mat `qlist'=J($qnum,1,.)
mat `tau_u'=J($qnum,1,.)
mat `tau_u_bc'=J($qnum,1,.)
mat `dmdt_plus' = J($qnum,1,.)
mat `dmdt_minus' = J($qnum,1,.)
mat `L1_plus' = J($qnum,1,.)
mat `L1_minus' = J($qnum,1,.)
mat `ifT_Rplus' = J($qnum,1,.)
mat `ifT_Rminus' = J($qnum,1,.)
mat `mi'=J($n,1,. )
mat `Vtau' = J($qnum,1,.)
mat `biasPi_u1' = J($qnum,1,.)
mat `biasRPi_u2' = J($qnum,1,.)
mat `biasTPi_u2' = J($qnum,1,.)
mat `biasTPi_u' = J($qnum,1,.)

local r=0
forvalues q=$minq($grid)$maxq {
  tempvar T_c T_c2 ZT ZT2 RT_c ZRT_c Y2 kern_T kern_T1 kern_prod kern_prod1 kern_fTRplus kern_fTRminus 
  local r=`r'+1
  
  quiet qreg T R Z ZR  [iweight=kern_R], quantile(`q') 
  mat `qlist'[`r',1]=`q'
  mat `qte'[`r',1]=_b[Z]
  
  /* 
  Record q^+ and q^- for choosing T1 and T0 in V_pi^m
  */
  mat `qplus'[`r',1] = _b[_cons] + _b[Z]
  mat `qminus'[`r',1] = _b[_cons]
  
  quiet gen `T_c'=T-`qminus'[`r',1]
  quiet replace `T_c'=T-`qplus'[`r',1] if R>=0
  quiet gen `T_c2'=`T_c'^2
  quiet gen `ZT'=`T_c'*Z
  quiet gen `ZT2'=`T_c2'*Z
  quiet gen `RT_c'=`T_c'*R
  quiet gen `ZRT_c'=`RT_c'*Z
  
  /*
  In the following, qte is set to be missing at the trimmed quantiles so they 
  will drop in the integration of tau_u to obtain pi. In addition, quantile 
  index is set to be zero, so in the double integration for variance 
  calculation, they will drop 
  */
  if abs(`qte'[`r',1])<trim[`r',1]{
    mat `qte'[`r',1]=.
    mat `qlist'[`r',1]=0
    mat `qplus'[`r',1]=.
    mat `qminus'[`r',1]=.
  }
  
  /*
  Use uniform kernel
  */
  quiet gen `kern_T'=0.5
  quiet replace `kern_T'=0 if abs(`T_c')>$h_T	
  quiet gen `kern_prod'=kern_R*`kern_T'
  
  quiet reg Y R `T_c' Z ZR `ZT' [iweight=`kern_prod']
  mat `tau_u'[`r',1]=_b[Z]/`qte'[`r',1]		

  /* 
  Estimate Variance of tau_u 
  Estimate sigma^{2,+/-} in V_tau 
  */
  quiet gen `kern_T1'=0.5
  quiet replace `kern_T1'=. if abs(`T_c')>$h_T1	
  quiet gen `kern_prod1'=kern_R1*`kern_T1'
  
  quiet reg Y R `T_c' Z ZR `ZT' [iweight=`kern_prod1']
  quiet gen `Y2' = (Y- _b[_cons] - _b[Z] )^2
  quiet replace `Y2' = (Y- _b[_cons])^2 if R < 0
  quiet reg `Y2' R `T_c' Z ZR `ZT' [iweight = `kern_prod1']
  scalar `sigma2plus' = _b[_cons] + _b[Z]
  scalar `sigma2minus' = _b[_cons]

  //Integration in Vpim+ and Vpim- //
	if `qte'[`r',1] !=.{
		local sigma2p =  `sigma2p' + `sigma2plus'*$grid			
		local sigma2m =  `sigma2m' + `sigma2minus'*$grid
  }
  
  /* 
  Parameters in V_tau. Estimate the joint density of R and T right above r0 
  */
  quiet gen `kern_fTRplus'=0.25
  quiet replace `kern_fTRplus'=0 if abs(`T_c')>($h_fplus*sd_T)|abs(R)>($h_fplus*sd_R)
  quiet sum `kern_fTRplus' if Z == 1
  scalar `fTRplus' = r(mean)/($h_fplus^2*sd_R*sd_T)
  
  /* 
  Estimate the reciprocal of the conditional density of T given R right 
  above r0. That is, ifT_Rplus = 1/f_{TR}^+ 
  */
  mat `ifT_Rplus'[`r',1] = fRplus/`fTRplus'		
  
  /* 
  Estimate the joint density of R and T right below r0
  */
  quiet gen `kern_fTRminus'=0.25
  quiet replace `kern_fTRminus'=0 if abs(`T_c')>($h_fminus*sd_T)|abs(R)>($h_fminus*sd_R)
  quiet sum `kern_fTRminus' if Z == 0
  scalar `fTRminus' = r(mean)/($h_fminus^2*sd_R*sd_T)
  
  /* 
  Estimate the reciprocal of the conditional density of T given R right 
  below r0. That is, ifT_R_minus = 1/f_{TR}^-
  */
  mat `ifT_Rminus'[`r',1] = fRminus/`fTRminus'		

  mat `Vtau'[`r',1] = 2*(`sigma2plus'*`ifT_Rplus'[`r',1] + `sigma2minus'*`ifT_Rminus'[`r',1])/($fR*(`qte'[`r',1])^2)

  /* 
  Estimate the bias of the estimated tau_u
  */
  quiet qreg T R R2 Z ZR ZR2 [iweight=kern_R1], quantile(`q') 
  scalar `biasT_minus'=2*_b[R2]*(-1/12)
  scalar `biasT_plus'=2*(_b[R2]+_b[ZR2])*(-1/12)	

  quiet reg Y R R2 `T_c' `T_c2' `RT_c' Z ZR `ZT' ZR2 `ZT2' `ZRT_c' [iweight=`kern_prod1']
  scalar `BR2'=2*(_b[ZR2])*(-1/12) 
  scalar `BT2'=2*(_b[`ZT2'])*(1/6)
  mat `dmdt_minus'[`r',1] =_b[`T_c']
  mat `dmdt_plus'[`r',1] =_b[`T_c']+_b[`ZT']	

  mat `L1_minus'[`r',1] =`dmdt_minus'[`r',1]*`ifT_Rminus'[`r',1]
	mat `L1_plus'[`r',1] =`dmdt_plus'[`r',1]*`ifT_Rplus'[`r',1]	
      
  scalar `biasRTau_u'=(`BR2'+`biasT_plus'*(`dmdt_plus'[`r',1]-`tau_u'[`r',1])-`biasT_minus'*(`dmdt_minus'[`r',1]-`tau_u'[`r',1]))/`qte'[`r',1]
  scalar `biasTTau_u'= `BT2'/`qte'[`r',1]
  
  mat `tau_u_bc'[`r',1]=`tau_u'[`r',1] - $h_R^2*`biasRTau_u' - $h_T^2*`biasTTau_u'

  //Estimated bias terms in biasPi//	
  mat `biasPi_u1'[`r',1]=(`biasT_plus'-`biasT_minus')/`qte'[`r',1]
  mat `biasRPi_u2'[`r',1]=`biasRTau_u'+(`biasT_plus'-`biasT_minus')*`tau_u'[`r',1]/`qte'[`r',1]
  mat `biasTPi_u2'[`r',1]=`biasTTau_u'
}
  
svmat `Vtau', names(`Vtau')

quiet gen `SEtau'= sqrt(`Vtau'/($n*$h_R*$h_T))	
sum `SEtau'

if $rho_1 >= 1 {
  local contCtau = 37.5*($rho_1/3 - 0.25)
}
if $rho_1 < 1 {
  local contCtau = 3.125*$rho_1^3
}

quiet gen `SEtau_bc' = sqrt( 1 + $rho_1^6*9.765625  + $rho_1*`contCtau'   )*`SEtau'
sum `SEtau'
sum `SEtau_bc'
mkmat `SEtau_bc' 

//Estimate pi//
svmat `qlist', names(`qlist')
svmat `qte', names(`qte')
svmat `tau_u', names(`tau_u' )
egen `w_sum0' = total(abs(`qte'))
scalar `w_sum' = `w_sum0'		
egen `pi0' = total(`tau_u'*abs(`qte')/`w_sum')
scalar `pi'=`pi0'

//Estimate bias of pi//
mat `biasRPi_u'=`biasRPi_u2'-`pi'*`biasPi_u1'
svmat `biasRPi_u', names(`biasRPi_u')
egen `biasRPi0'=total(`biasRPi_u'*abs(`qte')/`w_sum')
scalar `biasRPi'=`biasRPi0'

mat `biasTPi_u'=`biasTPi_u2'
svmat `biasTPi_u', names(`biasTPi_u')
egen `biasTPi0'=total(`biasTPi_u'*abs(`qte')/`w_sum')
scalar `biasTPi'=`biasTPi0'
scalar `pi_bc' = `pi' - $h_R^2*`biasRPi' - $h_T^2*`biasTPi'

* scalar list `biasTPi' `biasRPi' `pi' `pi_bc'

//Estimate Variance of pi: Vpi=VpimA+Vpiq //	
//Compute the adjustment term of Vpim: Ap, Am; Have computed the integration in Vpim: sigma2p and sigma2m//
svmat `qplus', names(`qplus')
svmat `qminus', names(`qminus')
tempvar Ap Am tsupp qub qlb sigma2A U L A1 A2 u1 u2 G1 G2

quiet sum `qplus'1 if `qte'1!=.
quiet gen `qub' = r(max)
quiet gen `qlb' = r(min)			
quiet gen `tsupp' = abs(`qub' - `qlb')/$h_T

quiet gen `u1'= ($Tubp - `qub')/$h_T
quiet gen `G1' = (`u1'+1)/2 
quiet replace `G1' = 1 if `u1' > 1
quiet replace `G1' = 0 if `u1' < -1

quiet gen `u2'= ($Tlbp - `qub')/$h_T
quiet gen `G2' = (`u2'+1)/2 
quiet replace `G2' = 0 if `u2' < -1
quiet replace `G2' = 1 if `u2' > 1

if `tsupp' >= 2{ 
  quiet gen `Ap' = `G1' - `G2'
  }
if `tsupp' < 2{
  quiet replace `u2' = (`qub' - $Tlbp)/$h_T
  quiet gen `U' = `u2' 
  quiet replace `U' = 1 if `u2' >= 1
  quiet replace `u1' = (`qub' - $Tubp)/$h_T
  quiet gen `L' = `u1' 
  quiet replace `L' = (`tsupp'-1) if `u1' < (`tsupp'-1)
  quiet gen `A1' = `U'^2/8 + (1-`tsupp')*`U'/4 - `L'^2/8 - (1-`tsupp')*`L'/4

  quiet replace `u2' = ($Tubp - `qlb')/$h_T
  quiet replace `U' = `u2' if `u2' < 1
  quiet replace `U' = 1 if `u2' >= 1
  quiet replace `u1' = ($Tlbp - `qlb')/$h_T
  quiet replace `L' = `u1' if `u1' >= (`tsupp'-1)
  quiet replace `L' = (`tsupp'-1) if `u1' < (`tsupp'-1)
  quiet gen `A2' = `U'^2/8 + (1-`tsupp')*`U'/4 - `L'^2/8 - (1-`tsupp')*`L'/4

  quiet gen `Ap' = `G1' - `G2' -`A1' - `A2'
  }

quiet sum `qminus'1 if `qte'1!=.
quiet replace `qub' = r(max)
quiet replace `qlb' = r(min)			
quiet replace `tsupp' = abs(`qub' - `qlb')/$h_T

quiet replace `u1'= ($Tubm - `qub')/$h_T
quiet replace `G1' = (`u1'+1)/2 if `u1' <= 1
quiet replace `G1' = 1 if `u1' > 1
quiet replace `G1' = 0 if `u1' < -1
quiet replace `u2'= ($Tlbm - `qub')/$h_T
quiet replace `G2' = (`u2'+1)/2 if `u2' >= -1
quiet replace `G2' = 0 if `u2' < -1
quiet replace `G2' = 1 if `u2' > 1

if `tsupp' >= 2{ 
  quiet gen `Am' = `G1' - `G2'
  }
if `tsupp' < 2{
  quiet replace `u2' = (`qub' - $Tlbm)/$h_T
  quiet replace `U' = `u2' if `u2' < 1
  quiet replace `U' = 1 if `u2' >= 1
  quiet replace `u1' = (`qub' - $Tubm)/$h_T
  quiet replace `L' = `u1' if `u1' >= (`tsupp'-1)
  quiet replace `L' = (`tsupp'-1) if `u1' < (`tsupp'-1)
  quiet replace `A1' = `U'^2/8 + (1-`tsupp')*`U'/4 - (`L'^2/8 + (1-`tsupp')*`L'/4)

  quiet replace `u2' = ($Tubm - `qlb')/$h_T
  quiet replace `U' = `u2' if `u2' < 1
  quiet replace `U' = 1 if `u2' >= 1
  quiet replace `u1' = ($Tlbm - `qlb')/$h_T
  quiet replace `L' = `u1' if `u1' >= (`tsupp'-1)
  quiet replace `L' = (`tsupp'-1) if `u1' < (`tsupp'-1)
  quiet replace `A2' = `U'^2/8 + (1-`tsupp')*`U'/4 - `L'^2/8 - (1-`tsupp')*`L'/4

  quiet gen `Am' = `G1' - `G2' -`A1' - `A2'
  }


//Estimate VpimA//
quiet gen `sigma2A' =`sigma2p'*`Ap' + `sigma2m'*`Am'
scalar VpimA = 4*`sigma2A'/($fR*`w_sum'^2*$grid^2)


  
//Estimate parameters in Vpiq //
tempname Lplus Lminus Lde
mat `Lplus' = (`L1_plus' -  `pi'*`ifT_Rplus')/(`w_sum'*$grid)
mat `Lminus' = (`L1_minus' - `pi'*`ifT_Rminus')/(`w_sum'*$grid)

local Ing = 0
forvalues j=1(1)$qnum {   
  tempname uj vk Lkj kj
  scalar `uj' = `qlist'[`j',1]

  forvalues k=1(1)$qnum{	
  scalar `vk' = `qlist'[`k',1]
  
  scalar `Lkj' = `Lplus'[`j',1]*`Lplus'[`k',1] + `Lminus'[`j',1]*`Lminus'[`k',1] 
  
  
  if `k' <= `j'{
    local Ing = `Ing' + `vk'*(1-`uj')*`Lkj'*$grid^2
    }	
  if `k' > `j'{	
    local Ing = `Ing' + `uj'*(1-`vk')*`Lkj'*$grid^2
    }
  }
}

scalar Vpiq = 4*`Ing'/$fR
scalar VpiA = VpimA + Vpiq
scalar SEpiA = sqrt(VpiA/($n*$h_R))	

if $rho_1 >= 1{
  local contCpi = 2.5 - 1.875/$rho_1
  }
if $rho_1 < 1{
  local contCpi = 3.125*$rho_1 - 2.5*$rho_1^3
  }

scalar Vpi_bcA = (1 + 1.640625*$rho_1^5 + `contCpi'*$rho_1^2 )*VpimA + Vpiq
scalar `SEpi_bcA' = sqrt(Vpi_bcA/($n*$h_R))
scalar list Vpi_bcA `SEpi_bcA'	

/* ereturn mat qlist=`qlist'	
ereturn mat qte=`qte'
ereturn mat tau_u_bc=`tau_u_bc'
ereturn mat SEtau_bc=`SEtau_bc' */
