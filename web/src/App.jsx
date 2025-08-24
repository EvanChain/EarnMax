import React, { useEffect, useState } from 'react'
import { ethers } from 'ethers'
import iaaveAbi from '../abi/IAaveV3PoolMinimal.json'
import faucetAbi from '../abi/Faucet.json'
import erc20Abi from '../abi/ERC20.json'
import routerAbi from '../abi/Router.json'
import pivAbi from '../abi/PIV.json'
import { DEPLOYMENTS } from './deployments'

const DEFAULTS = {
  AAVE_POOL: DEPLOYMENTS.MockAavePool,
  USDC: DEPLOYMENTS.MockUSDC,
  PENDLE_YIELD_DEFAULT: 14.0 // percent (editable by user)
}

export default function App() {
  const [provider, setProvider] = useState(null)
  const [signer, setSigner] = useState(null)
  const [account, setAccount] = useState(null)

  const [aavePool, setAavePool] = useState(DEFAULTS.AAVE_POOL)
  const [usdcAddr, setUsdcAddr] = useState(DEFAULTS.USDC)

  const [aaveRate, setAaveRate] = useState(null) // percent
  const [pendleYield, setPendleYield] = useState(DEFAULTS.PENDLE_YIELD_DEFAULT)

  const [leverage, setLeverage] = useState(1)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)
  // Simulation controls
  const [simulateAave, setSimulateAave] = useState(true)
  const [simulatedAaveRate, setSimulatedAaveRate] = useState(6.0) // percent

  const [faucetAddr] = useState(DEPLOYMENTS.Faucet)
  const [mockUSDCAddr, setMockUSDCAddr] = useState(null)
  const [mockPtAddr, setMockPtAddr] = useState(null)
  const [balances, setBalances] = useState({})

  // Positions state
  const [positions, setPositions] = useState([])
  const [positionsLoading, setPositionsLoading] = useState(false)

  const [routerAddr, setRouterAddr] = useState(DEPLOYMENTS.Router)
  const [userPivAddr, setUserPivAddr] = useState(null)
  const [deploying, setDeploying] = useState(false)
  const [diagInfo, setDiagInfo] = useState(null)

  // Default PIV address to scan for takeable positions
  const DEFAULT_SCAN_PIV_ADDR = '0x86954F830647d291186E90B1bB9C725f6901A9da'

  // Loan form state
  const [showLoanForm, setShowLoanForm] = useState(false)
  // now the form takes a principal (USDC) and a leverage multiplier; debt and collateral are computed automatically
  const [loanPrincipalInput, setLoanPrincipalInput] = useState('100') // principal in USDC
  const [loanSelectedLeverage, setLoanSelectedLeverage] = useState(3)
  const [loanInterestMode, setLoanInterestMode] = useState(2)
  const [loanSubmitting, setLoanSubmitting] = useState(false)
  const [loanApproving, setLoanApproving] = useState(false)
  const [loanTargetTokenPair, setLoanTargetTokenPair] = useState({ from: null, to: null })
  const [loanUseDeadlineDate, setLoanUseDeadlineDate] = useState(false)
  const [loanDeadlineDatetime, setLoanDeadlineDatetime] = useState('') // ISO-like local datetime string
  const [loanUseClosePrice, setLoanUseClosePrice] = useState(false)
  const [loanClosePriceInput, setLoanClosePriceInput] = useState('')
  const [principalAllowance, setPrincipalAllowance] = useState('0')

  // Take allowance state
  const [takeAllowance, setTakeAllowance] = useState('0')
  const [takeApproving, setTakeApproving] = useState(false)

  // Pricing / protocol limits used to compute amounts for the form
  const PT_PRICE_USDC = 0.8 // price of 1 PT in USDC
  const AAVE_LTV_LIMIT = 0.9 // 90% LTV

  // Simulated Pendle scenarios (local only, not on-chain)
  const PENDLE_SCENARIOS = [
    { id: 'baseline', label: '基线 (示例)', ptYield: 14.0, ptSdsdeYield: 5.0 },
    { id: 'high', label: '高收益 (示例)', ptYield: 20.0, ptSdsdeYield: 7.5 },
    { id: 'low', label: '低收益 (示例)', ptYield: 8.0, ptSdsdeYield: 3.0 }
  ]
  const [selectedScenario, setSelectedScenario] = useState(PENDLE_SCENARIOS[0].id)

  // keep pendleYield in sync when scenario changes
  useEffect(() => {
    const s = PENDLE_SCENARIOS.find(x => x.id === selectedScenario)
    if (s) setPendleYield(s.ptYield)
  }, [selectedScenario])

  // Initialize provider if MetaMask present
  useEffect(() => {
    if (window.ethereum) {
      const p = new ethers.providers.Web3Provider(window.ethereum, 'any')
      setProvider(p)
      // auto-connect if accounts already available
      p.listAccounts().then(accts => {
        if (accts && accts.length > 0) {
          setAccount(accts[0])
          setSigner(p.getSigner())
        }
      })
    }
  }, [])

  async function connectWallet() {
    if (!window.ethereum) {
      setError('No Web3 wallet found (MetaMask required)')
      return
    }
    try {
      const p = provider || new ethers.providers.Web3Provider(window.ethereum, 'any')
      const accounts = await p.send('eth_requestAccounts', [])
      setProvider(p)
      setSigner(p.getSigner())
      setAccount(accounts[0])
      setError(null)
    } catch (e) {
      setError(e.message)
    }
  }

  async function fetchAaveBorrowRate() {
    setLoading(true)
    setError(null)
    try {
      if (simulateAave) {
        // Use simulated Aave borrow rate instead of reading from chain
        setAaveRate(Number(simulatedAaveRate.toFixed(6)))
        return
      }
      const p = provider || new ethers.providers.JsonRpcProvider()
      const contract = new ethers.Contract(aavePool, iaaveAbi, p)
      const data = await contract.getReserveData(usdcAddr)
      // currentVariableBorrowRate is returned as a BigNumber in Ray (1e27) on Aave v3
      const raw = data.currentVariableBorrowRate ?? data.currentVariableBorrowRate.toString()
      // ensure BigNumber
      const bn = ethers.BigNumber.isBigNumber(raw) ? raw : ethers.BigNumber.from(raw.toString())
      // convert to floating percent: (bn / 1e27) * 100
      const ratePercent = Number(ethers.utils.formatUnits(bn, 27)) * 100
      setAaveRate(Number(ratePercent.toFixed(6)))
    } catch (e) {
      console.error('fetchAaveBorrowRate error', e)
      setError('无法获取 Aave 借款利率：' + (e.message || e.toString()))
      setAaveRate(null)
    } finally {
      setLoading(false)
    }
  }

  // fetch when pool or token changes
  useEffect(() => {
    fetchAaveBorrowRate()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [aavePool, usdcAddr])

  // load faucet token addresses
  useEffect(() => {
    async function load() {
      try {
        const p = provider || new ethers.providers.JsonRpcProvider()
        const faucetC = new ethers.Contract(faucetAddr, faucetAbi, p)
        const usdc = await faucetC.mockUSDC()
        const pt = await faucetC.mockPtSusde()
        setMockUSDCAddr(usdc)
        setMockPtAddr(pt)
      } catch (e) {
        console.warn('load faucet tokens failed', e)
      }
    }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [faucetAddr, provider])

  async function fetchTokenBalances() {
    if (!account) {
      setError('请先连接钱包以查看余额')
      return
    }
    setError(null)
    setLoading(true)
    try {
      const p = provider || new ethers.providers.JsonRpcProvider()
      const results = {}
      if (mockUSDCAddr) {
        const t = new ethers.Contract(mockUSDCAddr, erc20Abi, p)
        const [bal, dec] = await Promise.all([t.balanceOf(account), t.decimals()])
        results.mockUSDC = Number(ethers.utils.formatUnits(bal, dec))
      }
      if (mockPtAddr) {
        const t2 = new ethers.Contract(mockPtAddr, erc20Abi, p)
        const [bal2, dec2] = await Promise.all([t2.balanceOf(account), t2.decimals()])
        results.mockPT = Number(ethers.utils.formatUnits(bal2, dec2))
      }
      setBalances(results)
    } catch (e) {
      console.error('fetchTokenBalances error', e)
      setError('无法获取代币余额：' + (e.message || e.toString()))
    } finally {
      setLoading(false)
    }
  }

  async function callFaucet() {
    if (!signer) {
      setError('请先连接钱包以执行 faucet')
      return
    }
    setError(null)
    setLoading(true)
    try {
      const f = new ethers.Contract(faucetAddr, faucetAbi, signer)
      const tx = await f.faucet()
      await tx.wait()
      // refresh balances
      await fetchTokenBalances()
    } catch (e) {
      console.error('callFaucet error', e)
      setError('调用 faucet 失败：' + (e.message || e.toString()))
    } finally {
      setLoading(false)
    }
  }

  // fetch user's PIV mapping from Router
  async function fetchUserPiv() {
    if (!account) {
      setUserPivAddr(null)
      return
    }
    try {
      const p = provider || new ethers.providers.JsonRpcProvider()
      const routerC = new ethers.Contract(routerAddr, routerAbi, p)
      const addr = await routerC.userPivMapping(account)
      const zero = '0x0000000000000000000000000000000000000000'
      setUserPivAddr(addr && addr !== zero ? addr : null)
    } catch (e) {
      console.error('fetchUserPiv error', e)
      setError('无法读取 Router.userPivMapping: ' + (e.message || e.toString()))
    }
  }

  // call Router.deployPIV to create PIV on-chain (tx from connected signer)
  async function deployPivOnChain() {
    if (!signer) {
      setError('请先连接钱包以部署 PIV')
      return
    }
    setError(null)
    setDeploying(true)
    try {
      const routerWithSigner = new ethers.Contract(routerAddr, routerAbi, signer)
      const tx = await routerWithSigner.deployPIV()
      await tx.wait()
      // after deployment, read mapping
      await fetchUserPiv()
    } catch (e) {
      console.error('deployPivOnChain error', e)
      setError('部署 PIV 失败: ' + (e.message || e.toString()))
    } finally {
      setDeploying(false)
    }
  }

  // fetch mapping when account, provider or router changes
  useEffect(() => {
    fetchUserPiv()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account, provider, routerAddr])

  // Diagnostic function to help debug why PIV mapping might be missing
  async function diagnosePivMapping() {
    setLoading(true)
    setError(null)
    try {
      if (!provider) throw new Error('No provider (connect wallet first)')
      const net = await provider.getNetwork()
      const chainId = net.chainId
      const code = await provider.getCode(routerAddr)

      const routerC = new ethers.Contract(routerAddr, routerAbi, provider)
      const mapping = account ? await routerC.userPivMapping(account) : null

      // Attempt to read recent PIVDeployed events and find ones for this owner
      let events = []
      try {
        const filter = routerC.filters?.PIVDeployed ? routerC.filters.PIVDeployed() : null
        if (filter) {
          const logs = await routerC.queryFilter(filter, 0, 'latest')
          events = logs.map(l => ({ owner: l.args?.owner, piv: l.args?.pivAddress }))
        }
      } catch (e) {
        console.warn('queryFilter failed', e)
      }

      setDiagInfo({ chainId, routerCode: code, mapping: mapping && mapping !== '0x0000000000000000000000000000000000000000' ? mapping : null, events })
    } catch (e) {
      console.error('diagnosePivMapping error', e)
      setError('诊断失败：' + (e.message || e.toString()))
    } finally {
      setLoading(false)
    }
  }

  // Check USDC allowance for PIV contract
  async function checkPrincipalAllowance() {
    if (!signer || !account || !mockUSDCAddr) return
    try {
      const targetPivAddr = userPivAddr || PIV_FIXED_ADDR
      const usdcContract = new ethers.Contract(mockUSDCAddr, erc20Abi, signer)
      const allowance = await usdcContract.allowance(account, targetPivAddr)
      setPrincipalAllowance(ethers.utils.formatUnits(allowance, 6)) // USDC has 6 decimals
    } catch (e) {
      console.error('checkPrincipalAllowance error', e)
    }
  }

  // Check USDC allowance for Router contract (for take operations)
  async function checkTakeAllowance() {
    if (!signer || !account || !mockUSDCAddr) return
    try {
      const usdcContract = new ethers.Contract(mockUSDCAddr, erc20Abi, signer)
      const allowance = await usdcContract.allowance(account, routerAddr)
      setTakeAllowance(ethers.utils.formatUnits(allowance, 6)) // USDC has 6 decimals
    } catch (e) {
      console.error('checkTakeAllowance error', e)
    }
  }

  // Approve USDC for Router contract (for take operations)
  async function approveTake() {
    if (!signer || !mockUSDCAddr) {
      setError('请先连接钱包')
      return
    }
    
    const takeAmount = Number(takeAmountInput || '0')
    if (!(takeAmount > 0)) {
      setError('请输入有效的take金额')
      return
    }

    setTakeApproving(true)
    setError(null)
    try {
      const usdcContract = new ethers.Contract(mockUSDCAddr, erc20Abi, signer)
      const takeAmountBN = ethers.utils.parseUnits(takeAmount.toFixed(6), 6)
      
      const tx = await usdcContract.approve(routerAddr, takeAmountBN)
      await tx.wait()
      
      // refresh allowance
      await checkTakeAllowance()
      setError(`USDC 授权成功 (交易哈希: ${tx.hash})`)
    } catch (e) {
      console.error('approveTake error', e)
      setError('USDC 授权失败：' + (e.message || e.toString()))
    } finally {
      setTakeApproving(false)
    }
  }

  // Fetch user positions from PIV contract
  async function fetchPositions() {
    if (!account) {
      setPositions([])
      return
    }
    setPositionsLoading(true)
    try {
      const targetPivAddr = userPivAddr || PIV_FIXED_ADDR
      const p = provider || new ethers.providers.JsonRpcProvider()
      const piv = new ethers.Contract(targetPivAddr, pivAbi, p)
      
      // Get total positions count
      const totalPositions = await piv.totalPositions()
      const totalCount = totalPositions.toNumber()
      
      if (totalCount === 0) {
        setPositions([])
        return
      }
      
      // Fetch all positions (position IDs start from 1)
      const positionPromises = []
      for (let i = 1; i <= totalCount; i++) {
        positionPromises.push(piv.positionMapping(i))
      }
      
      const positionResults = await Promise.all(positionPromises)
      
      // Format positions data
      const formattedPositions = positionResults.map((pos, index) => {
        const positionId = index + 1
        return {
          id: positionId,
          collateralToken: pos.collateralToken,
          collateralAmount: ethers.utils.formatUnits(pos.collateralAmount, 18), // PT has 18 decimals
          debtToken: pos.debtToken,
          debtAmount: ethers.utils.formatUnits(pos.debtAmount.abs(), 6), // USDC has 6 decimals, use abs() for display
          principal: ethers.utils.formatUnits(pos.principal, 6),
          interestRateMode: pos.interestRateMode.toNumber(),
          expectProfit: ethers.utils.formatUnits(pos.expectProfit, 6),
          deadline: pos.deadline.toNumber(),
          // deadline 是限制他人 take position 的截止时间，过期后他人无法 take
          takeDeadlineExpired: pos.deadline.toNumber() > 0 && pos.deadline.toNumber() < Math.floor(Date.now() / 1000),
          // 仓位所有者随时可以平仓（不受 deadline 限制）
          canOwnerClose: true,
          // 他人可以 take 的条件：有预期利润且未过 deadline
          canOthersTake: pos.expectProfit.gt(0) && (pos.deadline.toNumber() === 0 || pos.deadline.toNumber() > Math.floor(Date.now() / 1000))
        }
      })
      
      setPositions(formattedPositions)
    } catch (e) {
      console.error('fetchPositions error', e)
      setError('无法获取 Positions 数据：' + (e.message || e.toString()))
    } finally {
      setPositionsLoading(false)
    }
  }

  // Approve USDC for PIV contract
  async function approvePrincipal() {
    if (!signer || !mockUSDCAddr) {
      setError('请先连接钱包')
      return
    }
    
    const principalNum = Number(loanPrincipalInput || '0')
    if (!(principalNum > 0)) {
      setError('请输入有效的本金金额')
      return
    }

    setLoanApproving(true)
    setError(null)
    try {
      const targetPivAddr = userPivAddr || PIV_FIXED_ADDR
      const usdcContract = new ethers.Contract(mockUSDCAddr, erc20Abi, signer)
      const principalAmount = ethers.utils.parseUnits(principalNum.toFixed(6), 6)
      
      const tx = await usdcContract.approve(targetPivAddr, principalAmount)
      await tx.wait()
      
      // refresh allowance
      await checkPrincipalAllowance()
      setError(`USDC 授权成功 (交易哈希: ${tx.hash})`)
    } catch (e) {
      console.error('approvePrincipal error', e)
      setError('USDC 授权失败：' + (e.message || e.toString()))
    } finally {
      setLoanApproving(false)
    }
  }

  async function createLoan(token) {
    // Open form so user can choose amounts for USDC -> PT-sUSDE
    if (!signer) {
      setError('请先连接钱包以发起杠杆操作')
      return
    }
    if (!mockUSDCAddr || !mockPtAddr) {
      setError('未检测到 MockUSDC 或 Mock PT 地址（请先调用 faucet）')
      return
    }
    // preset the token pair and default amounts
    setLoanTargetTokenPair({ from: mockUSDCAddr, to: mockPtAddr })
    // preset default principal and leverage
    setLoanPrincipalInput('100')
    setLoanSelectedLeverage(3)
    setLoanInterestMode(2)
    // check current allowance
    await checkPrincipalAllowance()
    setShowLoanForm(true)
  }

  async function submitCreateLoan() {
    if (!signer) {
      setError('请先连接钱包')
      return
    }
    
    const principalNum = Number(loanPrincipalInput || '0')
    const allowanceNum = Number(principalAllowance || '0')
    
    if (allowanceNum < principalNum) {
      setError('USDC 授权不足，请先授权本金金额')
      return
    }
    
    setLoanSubmitting(true)
    setError(null)
    try {
      const targetPivAddr = userPivAddr || PIV_FIXED_ADDR
      const piv = new ethers.Contract(targetPivAddr, pivAbi, signer)

      // ensure caller is owner (createPosition is onlyOwner)
      const owner = await piv.owner()
      if (owner.toLowerCase() !== account.toLowerCase()) {
        setError('当前钱包不是 PIV 合约的所有者，无法调用 createPosition。请部署或使用你自己的 PIV。')
        setLoanSubmitting(false)
        return
      }

      // parse user inputs: principal (USDC) + leverage -> compute debt (USDC) and collateral (PT)
      const collateralDecimals = 18
      const debtDecimals = 6
      const L = Number(loanSelectedLeverage || 1)

      if (!(principalNum > 0) || !(L >= 1)) {
        setError('请输入有效的本金与杠杆倍率')
        setLoanSubmitting(false)
        return
      }

      // Compute amounts in human units
      const debtNum = principalNum * (L - 1) // amount to borrow in USDC (this is the flashloan amount)
      const totalPositionValueUSDC = principalNum * L // total position value in USDC
      // required collateral value (in USDC) to support the borrow under Aave LTV
      const requiredCollateralValueUSDC = debtNum / AAVE_LTV_LIMIT
      // We'll use the total position value (principal * L) as collateral value; if that's less than requiredCollateralValueUSDC use requiredCollateralValueUSDC
      const collateralValueUSDC = Math.max(totalPositionValueUSDC, requiredCollateralValueUSDC)
      const collateralPT = collateralValueUSDC / PT_PRICE_USDC

      // Step 1: Prepare position data (PIV will pull principal via transferFrom)
      const principalAmount = ethers.utils.parseUnits(principalNum.toFixed(debtDecimals), debtDecimals)
      const debtAmount = ethers.utils.parseUnits(debtNum.toFixed(debtDecimals), debtDecimals) // This is flashloan amount, not total
      const collateralAmount = ethers.utils.parseUnits(collateralPT.toFixed(collateralDecimals), collateralDecimals)

      if (collateralAmount.lte(0)) {
        setError('请输入有效的抵押金额')
        setLoanSubmitting(false)
        return
      }
      
      // For 1x leverage, no debt is needed (debtAmount can be 0)
      if (L === 1 && debtAmount.gt(0)) {
        setError('1x 杠杆不需要借款，请检查杠杆设置')
        setLoanSubmitting(false)
        return
      }

      // compute expectProfit based on optional close price (close price = debt units per 1 collateral)
      let expectProfitBN = ethers.BigNumber.from(0)
      if (loanUseClosePrice && loanClosePriceInput && loanClosePriceInput.trim() !== '') {
        try {
          const closePriceScaled = ethers.utils.parseUnits(loanClosePriceInput.trim(), debtDecimals) // price in debt decimals per 1 collateral
          // value of collateral in debt token smallest units = collateralAmount * closePriceScaled / (10**collateralDecimals)
          const collateralScale = ethers.BigNumber.from(10).pow(collateralDecimals)
          const valueInDebt = collateralAmount.mul(closePriceScaled).div(collateralScale)
          // expected profit = max(0, valueInDebt - debtAmount)
          expectProfitBN = valueInDebt.gt(debtAmount) ? valueInDebt.sub(debtAmount) : ethers.BigNumber.from(0)
        } catch (err) {
          console.warn('invalid close price input', err)
          setError('平仓价格输入无效')
          setLoanSubmitting(false)
          return
        }
      }

      // compute deadline: prefer explicit datetime if enabled, otherwise hours from now
      const now = Math.floor(Date.now() / 1000)
      let deadlineTs = 0 // default to 0 (no deadline)
      if (loanUseDeadlineDate && loanDeadlineDatetime) {
        const parsed = Date.parse(loanDeadlineDatetime)
        if (!isNaN(parsed) && parsed / 1000 > now) {
          deadlineTs = Math.floor(parsed / 1000)
        } else {
          setError('请选择一个将来的到期时间')
          setLoanSubmitting(false)
          return
        }
      }

      // Step 2: Prepare swap data (MockSwapAdapter expects abi.encode(uint256))
      const MOCK_SWAP_ADAPTER = '0x83A313C7425F878D7c667599fC1e44505Fe990cf'
      const swapData = ethers.utils.defaultAbiCoder.encode(['uint256'], [collateralAmount])
      
      const swapUnits = [
        {
          adapter: MOCK_SWAP_ADAPTER,
          tokenIn: loanTargetTokenPair.from,
          tokenOut: loanTargetTokenPair.to,
          swapData: swapData
        }
      ]

      // Step 3: Prepare position struct (matching contract interface)
      const position = {
        collateralToken: loanTargetTokenPair.to,
        collateralAmount: collateralAmount.toString(),
        debtToken: loanTargetTokenPair.from,
        debtAmount: debtAmount.toString(), // This should be the flashloan amount (borrowing amount)
        principal: principalAmount.toString(), // Principal amount transferred to contract
        interestRateMode: loanInterestMode,
        expectProfit: expectProfitBN.toString(),
        deadline: deadlineTs
      }

      console.log('Position data:', position)
      console.log('Swap units:', swapUnits)

      // Step 4: Submit createPosition transaction (PIV will pull principal via transferFrom)
      const tx = await piv.createPosition(position, false, swapUnits)
      await tx.wait()
      setError('杠杆交易已提交（交易哈希: ' + tx.hash + '）')
      setShowLoanForm(false)
      // refresh balances and allowance
      await fetchTokenBalances()
      await checkPrincipalAllowance()
    } catch (e) {
      console.error('submitCreateLoan error', e)
      setError('创建杠杆贷款失败：' + (e.message || e.toString()))
    } finally {
      setLoanSubmitting(false)
    }
  }

  function cancelLoanForm() {
    setShowLoanForm(false)
    setError(null)
  }

  const amplifiedAave = aaveRate == null ? null : Number((aaveRate * leverage).toFixed(6))
  const amplifiedPendle = Number((pendleYield * leverage).toFixed(6))

  // Net leveraged yield (approximate): effective yield on equity when using leverage
  // Formula: netYield = pendleYield * leverage - aaveRate * (leverage - 1)
  const netLeveragedYield = (() => {
    const rAave = aaveRate == null ? 0 : aaveRate
    const rPendle = pendleYield || 0
    const L = leverage || 1
    const val = rPendle * L - rAave * (L - 1)
    return Number(val.toFixed(6))
  })()

  const totalBorrowCost = (() => {
    const rAave = aaveRate == null ? 0 : aaveRate
    const L = leverage || 1
    const cost = rAave * (L - 1)
    return Number(cost.toFixed(6))
  })()

  const grossPendle = (() => Number((pendleYield * leverage).toFixed(6)))()

  // Simulated token list for dex-like homepage
  const SIM_TOKENS = [
    { symbol: 'WETH', name: 'Wrapped Ether', baseYield: 8.5, decimals: 18 },
    { symbol: 'LPNT', name: 'Leverage Point Token', baseYield: 12.0, decimals: 18 },
    { symbol: 'PT-sUSDE', name: 'Pendle PT sUSDE', baseYield: 14.0, decimals: 18 },
    { symbol: 'PNTS', name: 'PointStable Token', baseYield: 4.0, decimals: 18 },
    { symbol: 'WBTC', name: 'Wrapped BTC', baseYield: 6.0, decimals: 8 }
  ]

  // per-token selected leverage (default 3x for demo)
  const [tokenLeverages, setTokenLeverages] = useState(() => {
    const m = {}
    SIM_TOKENS.forEach(t => (m[t.symbol] = 3))
    return m
  })

  // Show balance page state
  const [showBalancePage, setShowBalancePage] = useState(false)

  // Dex页面状态
  const [showDexPage, setShowDexPage] = useState(false)
  const [allPositions, setAllPositions] = useState([]) // 所有可take的仓位
  const [allPositionsLoading, setAllPositionsLoading] = useState(false)
  const [takePositionLoading, setTakePositionLoading] = useState(false)
  const [selectedTakePositions, setSelectedTakePositions] = useState([]) // 用户选择要take的仓位
  const [takeAmountInput, setTakeAmountInput] = useState('100') // take的USDC数量
  const [minAmountOut, setMinAmountOut] = useState('0') // 最小输出数量
  const [takeTokenPair, setTakeTokenPair] = useState({ tokenIn: null, tokenOut: null })

  // Auto-fetch positions when balance page is opened and account is connected
  useEffect(() => {
    if (showBalancePage && account && (userPivAddr || PIV_FIXED_ADDR)) {
      fetchPositions()
    }
  }, [showBalancePage, account, userPivAddr])

  // Auto-fetch all positions when dex page is opened
  useEffect(() => {
    if (showDexPage && account) {
      fetchAllPositions()
      checkTakeAllowance() // Also check take allowance when dex page opens
    }
  }, [showDexPage, account])

  // Check take allowance when take amount changes
  useEffect(() => {
    if (showDexPage && account && mockUSDCAddr) {
      checkTakeAllowance()
    }
  }, [takeAmountInput, showDexPage, account, mockUSDCAddr])

  function updateTokenLeverage(symbol, val) {
    setTokenLeverages(prev => ({ ...prev, [symbol]: val }))
  }

  // helper to shorten an address for display
  function shortAddress(addr) {
    if (!addr) return ''
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`
  }

  function calcNetYield(baseYield, L, aaveR) {
    // simplified model: gross = baseYield * L; borrow cost = aaveR * (L - 1); net = gross - cost
    const gross = baseYield * L
    const cost = aaveR * (L - 1)
    return { gross: Number(gross.toFixed(4)), cost: Number(cost.toFixed(4)), net: Number((gross - cost).toFixed(4)) }
  }

  // Fetch all available positions for taking (from default PIV address)
  async function fetchAllPositions() {
    setAllPositionsLoading(true)
    setError(null)
    try {
      const p = provider || new ethers.providers.JsonRpcProvider()
      
      // Use the default scan PIV address
      const pivAddresses = [DEFAULT_SCAN_PIV_ADDR]
      
      // Fetch positions from the default PIV contract
      const allPositionsData = []
      
      for (const pivAddr of pivAddresses) {
        try {
          const piv = new ethers.Contract(pivAddr, pivAbi, p)
          const totalPositions = await piv.totalPositions()
          const totalCount = totalPositions.toNumber()
          
          if (totalCount === 0) continue
          
          // Fetch all positions from this PIV
          const positionPromises = []
          for (let i = 1; i <= totalCount; i++) {
            positionPromises.push(piv.positionMapping(i))
          }
          
          const positionResults = await Promise.all(positionPromises)
          
          // Format and filter takeable positions
          for (let i = 0; i < positionResults.length; i++) {
            const pos = positionResults[i]
            const positionId = i + 1
            
            // Only include positions that can be taken by others
            const canTake = pos.expectProfit.gt(0) && 
                           (pos.deadline.toNumber() !== 0 || pos.deadline.toNumber() <= Math.floor(Date.now() / 1000))
            
            if (canTake) {
              allPositionsData.push({
                pivAddress: pivAddr,
                id: positionId,
                collateralToken: pos.collateralToken,
                collateralAmount: ethers.utils.formatUnits(pos.collateralAmount, 18),
                debtToken: pos.debtToken,
                debtAmount: ethers.utils.formatUnits(pos.debtAmount.abs(), 6),
                principal: ethers.utils.formatUnits(pos.principal, 6),
                interestRateMode: pos.interestRateMode.toNumber(),
                expectProfit: ethers.utils.formatUnits(pos.expectProfit, 6),
                deadline: pos.deadline.toNumber(),
                // Compute effective price: USDC per PT
                effectivePrice: pos.collateralAmount.gt(0) ? 
                  Number(ethers.utils.formatUnits(pos.expectProfit, 6)) / Number(ethers.utils.formatUnits(pos.collateralAmount, 18)) :
                  0,
                owner: await piv.owner()
              })
            }
          }
        } catch (e) {
          console.warn(`Failed to fetch positions from PIV ${pivAddr}:`, e)
        }
      }
      
      // Sort by effective price (best deals first)
      allPositionsData.sort((a, b) => a.effectivePrice - b.effectivePrice)
      
      setAllPositions(allPositionsData)
      
      // Auto-select token pair if we have positions
      if (allPositionsData.length > 0) {
        const firstPos = allPositionsData[0]
        setTakeTokenPair({
          tokenIn: firstPos.debtToken,
          tokenOut: firstPos.collateralToken
        })
      }
      
    } catch (e) {
      console.error('fetchAllPositions error', e)
      setError('无法获取可take的仓位：' + (e.message || e.toString()))
    } finally {
      setAllPositionsLoading(false)
    }
  }

  // Preview take position result
  async function previewTakePosition(pivAddress, positionId, inputAmount) {
    try {
      const p = provider || new ethers.providers.JsonRpcProvider()
      const piv = new ethers.Contract(pivAddress, pivAbi, p)
      const inputAmountBN = ethers.utils.parseUnits(inputAmount.toString(), 6) // USDC has 6 decimals
      const [debtInput, collateralOutput] = await piv.previewTakePosition(positionId, inputAmountBN)
      
      return {
        debtInput: ethers.utils.formatUnits(debtInput, 6),
        collateralOutput: ethers.utils.formatUnits(collateralOutput, 18)
      }
    } catch (e) {
      console.error('previewTakePosition error', e)
      return { debtInput: '0', collateralOutput: '0' }
    }
  }

  // Execute take position via Router
  async function executeTakePosition() {
    if (!signer || !account) {
      setError('请先连接钱包')
      return
    }
    
    if (selectedTakePositions.length === 0) {
      setError('请至少选择一个仓位')
      return
    }
    
    const takeAmount = Number(takeAmountInput || '0')
    const minOut = Number(minAmountOut || '0')
    
    if (!(takeAmount > 0)) {
      setError('请输入有效的take金额')
      return
    }

    // Check allowance before proceeding
    const currentAllowance = Number(takeAllowance || '0')
    if (currentAllowance < takeAmount) {
      setError('USDC 授权不足，请先授权足够的金额')
      return
    }
    
    setTakePositionLoading(true)
    setError(null)
    
    try {
      // Check USDC allowance for Router
      if (!mockUSDCAddr) {
        setError('未检测到USDC地址')
        return
      }
      
      const takeAmountBN = ethers.utils.parseUnits(takeAmount.toFixed(6), 6)
      
      // Prepare position data for Router
      const positionDatas = selectedTakePositions.map(pos => ({
        pivAddress: pos.pivAddress,
        positionId: pos.id
      }))
      
      const swapData = {
        tokenIn: takeTokenPair.tokenIn || mockUSDCAddr,
        tokenOut: takeTokenPair.tokenOut || mockPtAddr,
        amountIn: takeAmountBN.toString(),
        minAmountOut: ethers.utils.parseUnits(minOut.toFixed(18), 18).toString(),
        positionDatas: positionDatas
      }
      
      console.log('Swap data:', swapData)
      
      // Execute swap via Router
      const routerWithSigner = new ethers.Contract(routerAddr, routerAbi, signer)
      const tx = await routerWithSigner.swap(swapData)
      await tx.wait()
      
      setError(`Take position 成功! (交易哈希: ${tx.hash})`)
      
      // Refresh positions, balances, and allowances
      await fetchAllPositions()
      await fetchTokenBalances()
      await checkTakeAllowance()
      
      // Clear selections
      setSelectedTakePositions([])
      
    } catch (e) {
      console.error('executeTakePosition error', e)
      setError('Take position 失败：' + (e.message || e.toString()))
    } finally {
      setTakePositionLoading(false)
    }
  }

  // Toggle position selection for taking
  function togglePositionSelection(position) {
    setSelectedTakePositions(prev => {
      const isSelected = prev.some(p => p.pivAddress === position.pivAddress && p.id === position.id)
      if (isSelected) {
        return prev.filter(p => !(p.pivAddress === position.pivAddress && p.id === position.id))
      } else {
        return [...prev, position]
      }
    })
  }

  return (
    <div className="app" style={{ boxSizing: 'border-box', maxWidth: 1200, margin: '0 auto', padding: 16 }}>
      {/* Responsive reset to avoid overflow on small screens */}
      <style>{`.app * { box-sizing: border-box; } input, textarea, select, button { max-width: 100%; } .app { -webkit-font-smoothing:antialiased; }`}</style>

      {/* Top bar: wallet connect and PIV info */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{ fontWeight: 700 }}>EarnMax</div>
          <div style={{ color: 'var(--muted)', fontSize: 13 }}></div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          {account ? (
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ textAlign: 'right' }}>
                <div style={{ fontSize: 12, color: 'var(--muted)' }}>已连接</div>
                <div style={{ fontWeight: 700 }}>{shortAddress(account)}</div>
              </div>
              <button onClick={() => { setSigner(null); setAccount(null); }} style={{ padding: '8px 12px', borderRadius: 8, background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.04)', cursor: 'pointer' }}>断开</button>
            </div>
          ) : (
            <button onClick={connectWallet} style={{ padding: '8px 14px', borderRadius: 8, background: 'linear-gradient(90deg,#7c3aed,#3b82f6)', color: 'white', border: 'none', cursor: 'pointer' }}>连接钱包</button>
          )}

          {/* Faucet button moved to top bar for convenience */}
          <button onClick={callFaucet} disabled={loading || !signer} style={{ padding: '8px 12px', borderRadius: 8, background: '#10b981', color: 'white', border: 'none', cursor: signer ? 'pointer' : 'not-allowed' }}>领取 Faucet</button>

          {/* Balance page toggle button */}
          <button onClick={() => setShowBalancePage(!showBalancePage)} style={{ padding: '8px 12px', borderRadius: 8, background: '#6366f1', color: 'white', border: 'none', cursor: 'pointer' }}>
            {showBalancePage ? '返回首页' : 'DashBoard'}
          </button>

          {/* Dex page toggle button */}
          <button onClick={() => {
            setShowDexPage(!showDexPage);
            setShowBalancePage(false);
          }} style={{ padding: '8px 12px', borderRadius: 8, background: '#f59e0b', color: 'white', border: 'none', cursor: 'pointer' }}>
            {showDexPage ? '返回首页' : 'Dex Take'}
          </button>

          <div style={{ width: 1, height: 28, background: 'rgba(255,255,255,0.03)' }} />

          <div style={{ textAlign: 'right' }}>
            {userPivAddr ? (
              <div>
                <div style={{ fontSize: 12, color: 'var(--muted)' }}>PIV 合约</div>
                <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
                  <a href={`https://etherscan.io/address/${userPivAddr}`} target="_blank" rel="noreferrer" style={{ color: '#9ae6b4', fontWeight: 700 }}>{shortAddress(userPivAddr)}</a>
                  <button onClick={fetchUserPiv} style={{ padding: '6px 10px', borderRadius: 8, background: 'rgba(255,255,255,0.02)', border: '1px solid rgba(255,255,255,0.04)' }}>刷新</button>
                </div>
              </div>
            ) : (
              <div>
                <div style={{ fontSize: 12, color: 'var(--muted)' }}>PIV 合约</div>
                <div style={{ display: 'flex', gap: 8 }}>
                  <button onClick={deployPivOnChain} disabled={deploying || !signer} style={{ padding: '8px 12px', borderRadius: 8, background: deploying ? 'rgba(255,255,255,0.03)' : 'linear-gradient(90deg,#34d399,#10b981)', color: 'white', border: 'none', cursor: 'pointer' }}>{deploying ? '部署中...' : '创建 PIV'}</button>
                  <button onClick={fetchUserPiv} style={{ padding: '6px 10px', borderRadius: 8, background: 'rgba(255,255,255,0.02)', border: '1px solid rgba(255,255,255,0.04)' }}>刷新</button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {showBalancePage ? (
        /* Balance Page */
        <div style={{
          background: 'linear-gradient(90deg, rgba(124,58,237,0.12), rgba(59,130,246,0.06))',
          padding: 18,
          borderRadius: 12,
          marginBottom: 18
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 18 }}>
            <div>
              <h1 style={{ margin: 0 }}>Assets</h1>
              <div style={{ color: 'var(--muted)', marginTop: 6 }}>查看您账户中的代币余额</div>
            </div>
            <button 
              onClick={fetchTokenBalances} 
              disabled={loading || !account} 
              style={{ 
                padding: '8px 16px', 
                borderRadius: 8, 
                background: loading ? '#9ca3af' : '#10b981', 
                color: 'white', 
                border: 'none', 
                cursor: loading ? 'not-allowed' : 'pointer' 
              }}
            >
              {loading ? '刷新中...' : '刷新余额'}
            </button>
          </div>

          {!account ? (
            <div style={{ textAlign: 'center', padding: 40, color: 'var(--muted)' }}>
              请先连接钱包以查看余额
            </div>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: 16 }}>
              {/* MockUSDC Balance Card */}
              <div style={{ background: 'rgba(255,255,255,0.02)', padding: 18, borderRadius: 12, border: '1px solid rgba(255,255,255,0.04)' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
                  <div>
                    <div style={{ fontWeight: 700, fontSize: 18 }}>MockUSDC</div>
                    <div style={{ fontSize: 12, color: 'var(--muted)' }}>测试用 USDC 代币</div>
                  </div>
                  <div style={{ width: 40, height: 40, borderRadius: '50%', background: '#2563eb', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 700 }}>
                    U
                  </div>
                </div>
                <div style={{ marginBottom: 12 }}>
                  <div style={{ fontSize: 24, fontWeight: 900 }}>
                    {balances.mockUSDC != null ? balances.mockUSDC.toFixed(2) : '—'}
                  </div>
                  <div style={{ fontSize: 12, color: 'var(--muted)' }}>USDC</div>
                </div>
                <div style={{ fontSize: 12, color: 'var(--muted)', marginBottom: 8 }}>
                  合约地址: {mockUSDCAddr ? shortAddress(mockUSDCAddr) : '加载中...'}
                </div>
                {mockUSDCAddr && (
                  <a 
                    href={`https://etherscan.io/address/${mockUSDCAddr}`} 
                    target="_blank" 
                    rel="noreferrer" 
                    style={{ fontSize: 12, color: '#60a5fa', textDecoration: 'none' }}
                  >
                    在 Etherscan 查看 →
                  </a>
                )}
              </div>

              {/* MockPT Balance Card */}
              <div style={{ background: 'rgba(255,255,255,0.02)', padding: 18, borderRadius: 12, border: '1px solid rgba(255,255,255,0.04)' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
                  <div>
                    <div style={{ fontWeight: 700, fontSize: 18 }}>Mock PT-sUSDE</div>
                    <div style={{ fontSize: 12, color: 'var(--muted)' }}>测试用 Pendle PT 代币</div>
                  </div>
                  <div style={{ width: 40, height: 40, borderRadius: '50%', background: '#7c3aed', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 700 }}>
                    PT
                  </div>
                </div>
                <div style={{ marginBottom: 12 }}>
                  <div style={{ fontSize: 24, fontWeight: 900 }}>
                    {balances.mockPT != null ? balances.mockPT.toFixed(4) : '—'}
                  </div>
                  <div style={{ fontSize: 12, color: 'var(--muted)' }}>PT</div>
                </div>
                <div style={{ fontSize: 12, color: 'var(--muted)', marginBottom: 8 }}>
                  合约地址: {mockPtAddr ? shortAddress(mockPtAddr) : '加载中...'}
                </div>
                {mockPtAddr && (
                  <a 
                    href={`https://etherscan.io/address/${mockPtAddr}`} 
                    target="_blank" 
                    rel="noreferrer" 
                    style={{ fontSize: 12, color: '#60a5fa', textDecoration: 'none' }}
                  >
                    在 Etherscan 查看 →
                  </a>
                )}
              </div>

              {/* Faucet Info Card */}
              <div style={{ background: 'rgba(16,185,129,0.05)', padding: 18, borderRadius: 12, border: '1px solid rgba(16,185,129,0.2)' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
                  <div>
                    <div style={{ fontWeight: 700, fontSize: 18, color: '#10b981' }}>Faucet</div>
                    <div style={{ fontSize: 12, color: 'var(--muted)' }}>获取测试代币</div>
                  </div>
                  <div style={{ width: 40, height: 40, borderRadius: '50%', background: '#10b981', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 700 }}>
                    🚰
                  </div>
                </div>
                <div style={{ marginBottom: 12 }}>
                  <div style={{ fontSize: 14, marginBottom: 8 }}>
                    点击顶部 "领取 Faucet" 按钮可获得：
                  </div>
                  <div style={{ fontSize: 12, color: 'var(--muted)' }}>
                    • MockUSDC: 用于杠杆交易本金<br/>
                    • Mock PT-sUSDE: 测试用抵押品
                  </div>
                </div>
                <div style={{ fontSize: 12, color: 'var(--muted)', marginBottom: 8 }}>
                  Faucet 合约: {shortAddress(faucetAddr)}
                </div>
                <a 
                  href={`https://etherscan.io/address/${faucetAddr}`} 
                  target="_blank" 
                  rel="noreferrer" 
                  style={{ fontSize: 12, color: '#10b981', textDecoration: 'none' }}
                >
                  在 Etherscan 查看 →
                </a>
              </div>
            </div>
          )}

          {/* Positions Section */}
          {account && (
            <div style={{ marginTop: 24 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 18 }}>
                <div>
                  <h2 style={{ margin: 0 }}>我的杠杆仓位</h2>
                  <div style={{ color: 'var(--muted)', marginTop: 6, fontSize: 14 }}>
                    查看您在 PIV 合约中的所有杠杆仓位
                  </div>
                </div>
                <button 
                  onClick={fetchPositions} 
                  disabled={positionsLoading} 
                  style={{ 
                    padding: '8px 16px', 
                    borderRadius: 8, 
                    background: positionsLoading ? '#9ca3af' : '#7c3aed', 
                    color: 'white', 
                    border: 'none', 
                    cursor: positionsLoading ? 'not-allowed' : 'pointer' 
                  }}
                >
                  {positionsLoading ? '加载中...' : '刷新仓位'}
                </button>
              </div>

              {positionsLoading ? (
                <div style={{ textAlign: 'center', padding: 40, color: 'var(--muted)' }}>
                  正在加载仓位数据...
                </div>
              ) : positions.length === 0 ? (
                <div style={{ 
                  textAlign: 'center', 
                  padding: 40, 
                  background: 'rgba(255,255,255,0.02)', 
                  borderRadius: 12, 
                  border: '1px solid rgba(255,255,255,0.04)' 
                }}>
                  <div style={{ fontSize: 18, marginBottom: 8 }}>🏦</div>
                  <div style={{ color: 'var(--muted)' }}>暂无杠杆仓位</div>
                  <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 6 }}>
                    返回首页创建您的第一个杠杆仓位
                  </div>
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(350px, 1fr))', gap: 16 }}>
                  {positions.map(position => (
                    <div key={position.id} style={{ 
                      background: 'rgba(255,255,255,0.02)', 
                      padding: 18, 
                      borderRadius: 12, 
                      border: '1px solid rgba(255,255,255,0.04)' 
                    }}>
                      {/* Position Header */}
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                        <div>
                          <div style={{ fontWeight: 700, fontSize: 18 }}>Position #{position.id}</div>
                          <div style={{ fontSize: 12, color: 'var(--muted)' }}>
                            {position.collateralToken === mockPtAddr ? 'PT-sUSDE' : shortAddress(position.collateralToken)} 
                            {' → '} 
                            {position.debtToken === mockUSDCAddr ? 'USDC' : shortAddress(position.debtToken)}
                          </div>
                        </div>
                        <div style={{ 
                          padding: '4px 8px', 
                          borderRadius: 6, 
                          fontSize: 12, 
                          fontWeight: 700,
                          background: position.canOthersTake ? '#10b981' : position.takeDeadlineExpired ? '#ef4444' : '#6b7280',
                          color: 'white'
                        }}>
                          {position.canOthersTake ? 'Take 开放' : position.takeDeadlineExpired ? 'Take 过期' : '活跃中'}
                        </div>
                      </div>

                      {/* Position Details */}
                      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 12 }}>
                        <div>
                          <div style={{ fontSize: 12, color: 'var(--muted)' }}>本金</div>
                          <div style={{ fontWeight: 700 }}>{Number(position.principal).toFixed(2)} USDC</div>
                        </div>
                        <div>
                          <div style={{ fontSize: 12, color: 'var(--muted)' }}>债务</div>
                          <div style={{ fontWeight: 700, color: '#ef4444' }}>{Number(position.debtAmount).toFixed(2)} USDC</div>
                        </div>
                        <div>
                          <div style={{ fontSize: 12, color: 'var(--muted)' }}>抵押品</div>
                          <div style={{ fontWeight: 700 }}>{Number(position.collateralAmount).toFixed(4)} PT</div>
                        </div>
                        <div>
                          <div style={{ fontSize: 12, color: 'var(--muted)' }}>利率模式</div>
                          <div style={{ fontWeight: 700 }}>{position.interestRateMode === 1 ? 'Stable' : 'Variable'}</div>
                        </div>
                      </div>

                      {/* Profit & Deadline Info */}
                      {(Number(position.expectProfit) > 0 || position.deadline > 0) && (
                        <div style={{ 
                          borderTop: '1px solid rgba(255,255,255,0.04)', 
                          paddingTop: 12, 
                          marginTop: 12 
                        }}>
                          {Number(position.expectProfit) > 0 && (
                            <div style={{ marginBottom: 8 }}>
                              <div style={{ fontSize: 12, color: 'var(--muted)' }}>预期利润</div>
                              <div style={{ fontWeight: 700, color: '#10b981' }}>
                                {Number(position.expectProfit).toFixed(2)} USDC
                              </div>
                            </div>
                          )}
                          {position.deadline > 0 && (
                            <div>
                              <div style={{ fontSize: 12, color: 'var(--muted)' }}>截止时间</div>
                              <div style={{ 
                                fontWeight: 700, 
                                color: position.takeDeadlineExpired ? '#ef4444' : '#6b7280' 
                              }}>
                                {new Date(position.deadline * 1000).toLocaleString()}
                              </div>
                            </div>
                          )}
                        </div>
                      )}

                      {/* Action Buttons */}
                      <div style={{ marginTop: 16, display: 'flex', gap: 8 }}>
                        <button 
                          disabled={!position.canOwnerClose}
                          style={{ 
                            flex: 1,
                            padding: '8px 12px', 
                            borderRadius: 6, 
                            background: position.canOwnerClose ? '#10b981' : '#6b7280', 
                            color: 'white', 
                            border: 'none',
                            cursor: position.canOwnerClose ? 'pointer' : 'not-allowed',
                            fontSize: 12
                          }}
                        >
                          {position.canOwnerClose ? '平仓获利' : '暂不可平仓'}
                        </button>
                        <button 
                          style={{ 
                            padding: '8px 12px', 
                            borderRadius: 6, 
                            background: 'rgba(255,255,255,0.05)', 
                            color: 'white', 
                            border: '1px solid rgba(255,255,255,0.1)',
                            cursor: 'pointer',
                            fontSize: 12
                          }}
                        >
                          详情
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      ) : showDexPage ? (
        /* Dex Take Page */
        <div style={{
          background: 'linear-gradient(90deg, rgba(245,158,11,0.12), rgba(249,115,22,0.06))',
          padding: 18,
          borderRadius: 12,
          marginBottom: 18
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 18 }}>
            <div>
              <h1 style={{ margin: 0 }}>🔥 Dex Take Positions</h1>
              <div style={{ color: 'var(--muted)', marginTop: 6 }}>
                正在扫描可take仓位
              </div>
            </div>
            {/* 移除扫描按钮，改为显示状态 */}
            <div style={{ 
              padding: '8px 16px', 
              borderRadius: 8, 
              background: allPositionsLoading ? '#9ca3af' : '#10b981', 
              color: 'white', 
              fontSize: 14,
              fontWeight: 600
            }}>
              {allPositionsLoading ? '⏳ 扫描中...' : `✅ 已发现 ${allPositions.length} 个仓位`}
            </div>
          </div>

          {!account ? (
            <div style={{ textAlign: 'center', padding: 40, color: 'var(--muted)' }}>
              请先连接钱包以使用Dex功能
            </div>
          ) : (
            <>
              {/* Take Position Control Panel */}
              <div style={{ 
                background: 'rgba(255,255,255,0.02)', 
                padding: 18, 
                borderRadius: 12, 
                border: '1px solid rgba(255,255,255,0.04)',
                marginBottom: 18
              }}>
                <h3 style={{ margin: '0 0 16px 0', color: '#f59e0b' }}>⚡ Take Position 操作面板</h3>
                
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: 16, marginBottom: 16 }}>
                  {/* Take Amount Input */}
                  <div>
                    <label style={{ display: 'block', marginBottom: 6, fontSize: 14, fontWeight: 600 }}>
                      Take 金额 (USDC)
                    </label>
                    <input 
                      type="number" 
                      value={takeAmountInput} 
                      onChange={e => setTakeAmountInput(e.target.value)}
                      placeholder="输入USDC数量" 
                      style={{ 
                        width: '100%', 
                        padding: '10px', 
                        borderRadius: 8, 
                        border: '1px solid rgba(255,255,255,0.1)',
                        background: 'rgba(255,255,255,0.05)',
                        color: 'white'
                      }} 
                    />
                  </div>

                  {/* Min Amount Out */}
                  <div>
                    <label style={{ display: 'block', marginBottom: 6, fontSize: 14, fontWeight: 600 }}>
                      最小输出 (PT)
                    </label>
                    <input 
                      type="number" 
                      value={minAmountOut} 
                      onChange={e => setMinAmountOut(e.target.value)}
                      placeholder="最小PT输出数量" 
                      style={{ 
                        width: '100%', 
                        padding: '10px', 
                        borderRadius: 8, 
                        border: '1px solid rgba(255,255,255,0.1)',
                        background: 'rgba(255,255,255,0.05)',
                        color: 'white'
                      }} 
                    />
                  </div>
                </div>

                {/* USDC 授权状态 */}
                <div style={{ 
                  marginBottom: 16, 
                  padding: 12, 
                  background: 'rgba(16,185,129,0.05)', 
                  borderRadius: 8, 
                  border: '1px solid rgba(16,185,129,0.2)' 
                }}>
                  <div style={{ fontSize: 14, color: '#10b981', marginBottom: 8, fontWeight: 600 }}>
                    💰 USDC 授权状态
                  </div>
                  <div style={{ fontSize: 13, color: 'white', marginBottom: 8 }}>
                    当前授权余额: <strong>{Number(takeAllowance).toFixed(2)} USDC</strong>
                    {Number(takeAllowance) < Number(takeAmountInput || '0') && (
                      <span style={{ color: '#ef4444', marginLeft: 8 }}>⚠️ 授权不足</span>
                    )}
                  </div>
                  <button 
                    onClick={approveTake} 
                    disabled={takeApproving || !takeAmountInput || Number(takeAmountInput) <= 0} 
                    style={{ 
                      padding: '8px 16px', 
                      background: takeApproving ? '#9ca3af' : '#10b981', 
                      color: 'white', 
                      border: 'none', 
                      borderRadius: 6,
                      cursor: takeApproving ? 'not-allowed' : 'pointer',
                      fontSize: 14,
                      fontWeight: 600
                    }}
                  >
                    {takeApproving ? '🔄 授权中...' : '✅ 授权 USDC'}
                  </button>
                </div>

                {/* Execute Button */}
                <button 
                  onClick={executeTakePosition}
                  disabled={takePositionLoading || selectedTakePositions.length === 0 || !takeAmountInput || Number(takeAmountInput) <= 0 || Number(takeAllowance) < Number(takeAmountInput || '0')}
                  style={{ 
                    width: '100%',
                    padding: '12px 24px', 
                    borderRadius: 8, 
                    background: (takePositionLoading || selectedTakePositions.length === 0 || !takeAmountInput || Number(takeAmountInput) <= 0 || Number(takeAllowance) < Number(takeAmountInput || '0')) 
                      ? '#6b7280' 
                      : 'linear-gradient(90deg, #f59e0b, #f97316)', 
                    color: 'white', 
                    border: 'none',
                    cursor: (takePositionLoading || selectedTakePositions.length === 0 || !takeAmountInput || Number(takeAmountInput) <= 0 || Number(takeAllowance) < Number(takeAmountInput || '0')) 
                      ? 'not-allowed' 
                      : 'pointer',
                    fontSize: 16,
                    fontWeight: 600
                  }}
                >
                  {takePositionLoading ? '⏳ 执行中...' : 
                   Number(takeAllowance) < Number(takeAmountInput || '0') ? '❌ 需要先授权 USDC' :
                   `🚀 Execute Take (${selectedTakePositions.length} positions)`}
                </button>
              </div>

              {/* Available Positions List */}
              <div style={{ marginTop: 24 }}>
                <h3 style={{ margin: '0 0 16px 0' }}>📋 可Take的仓位列表</h3>
                
                {allPositionsLoading ? (
                  <div style={{ textAlign: 'center', padding: 40, color: 'var(--muted)' }}>
                    正在扫描所有PIV合约中的可take仓位...
                  </div>
                ) : allPositions.length === 0 ? (
                  <div style={{ 
                    textAlign: 'center', 
                    padding: 40, 
                    background: 'rgba(255,255,255,0.02)', 
                    borderRadius: 12, 
                    border: '1px solid rgba(255,255,255,0.04)' 
                  }}>
                    <div style={{ fontSize: 18, marginBottom: 8 }}>🔍</div>
                    <div style={{ color: 'var(--muted)' }}>暂无可take的仓位</div>
                    <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 6 }}>
                      请稍后刷新或等待其他用户创建可take的仓位
                    </div>
                  </div>
                ) : (
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(380px, 1fr))', gap: 16 }}>
                    {allPositions.map((position, index) => {
                      const isSelected = selectedTakePositions.some(p => p.pivAddress === position.pivAddress && p.id === position.id)
                      
                      return (
                        <div 
                          key={`${position.pivAddress}-${position.id}`} 
                          style={{ 
                            background: isSelected ? 'rgba(245,158,11,0.15)' : 'rgba(255,255,255,0.02)', 
                            padding: 18, 
                            borderRadius: 12, 
                            border: isSelected ? '2px solid #f59e0b' : '1px solid rgba(255,255,255,0.04)',
                            cursor: 'pointer',
                            transition: 'all 0.2s ease'
                          }}
                          onClick={() => togglePositionSelection(position)}
                        >
                          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                            <div>
                              <div style={{ fontWeight: 700, fontSize: 18 }}>
                                Position #{position.id}
                                {isSelected && <span style={{ color: '#f59e0b', marginLeft: 8 }}>✓</span>}
                              </div>
                              <div style={{ fontSize: 12, color: 'var(--muted)' }}>
                                PIV: {shortAddress(position.pivAddress)}
                              </div>
                            </div>
                            <div style={{ 
                              padding: '4px 8px', 
                              borderRadius: 6, 
                              fontSize: 12, 
                              fontWeight: 700,
                              background: '#10b981',
                              color: 'white'
                            }}>
                              Available
                            </div>
                          </div>

                          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
                            <div>
                              <div style={{ fontSize: 12, color: 'var(--muted)' }}>抵押品</div>
                              <div style={{ fontWeight: 700 }}>{Number(position.collateralAmount).toFixed(4)} PT</div>
                            </div>
                            <div>
                              <div style={{ fontSize: 12, color: 'var(--muted)' }}>预期利润</div>
                              <div style={{ fontWeight: 700, color: '#10b981' }}>{Number(position.expectProfit).toFixed(2)} USDC</div>
                            </div>
                          </div>

                          <div style={{ 
                            fontSize: 11, 
                            color: 'var(--muted)', 
                            textAlign: 'center',
                            marginTop: 12,
                            fontStyle: 'italic'
                          }}>
                            {isSelected ? '✓ 已选择，点击取消选择' : '点击选择此仓位进行take'}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                )}
              </div>
            </>
          )}
        </div>
      ) : (
        /* Main Page - Dex-style header + token list */
        <div style={{
          background: 'linear-gradient(90deg, rgba(124,58,237,0.12), rgba(59,130,246,0.06))',
          padding: 18,
          borderRadius: 12,
          marginBottom: 18
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h1 style={{ margin: 0 }}>EarnMax</h1>
              <div style={{ color: 'var(--muted)', marginTop: 6 }}>快速查看多种资产在不同杠杆下的示例年化收益，仅供参考。</div>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ color: 'var(--muted)' }}>Aave 借出利率</div>
              <div style={{ fontWeight: 700, fontSize: 18 }}>{aaveRate == null ? `${simulatedAaveRate}%` : `${aaveRate}%`}</div>
            </div>
          </div>

          <div style={{ marginTop: 18 }}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 12 }}>
              {SIM_TOKENS.map(token => {
                const L = tokenLeverages[token.symbol] || 1
                const { gross, cost, net } = calcNetYield(token.baseYield, L, aaveRate == null ? simulatedAaveRate : aaveRate)
                return (
                  <div key={token.symbol} style={{ background: 'rgba(255,255,255,0.02)', padding: 12, borderRadius: 10 }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <div>
                        <div style={{ fontWeight: 700 }}>{token.symbol}</div>
                        <div style={{ fontSize: 12, color: 'var(--muted)' }}>{token.name}</div>
                      </div>
                      <div style={{ textAlign: 'right' }}>
                        <div style={{ fontSize: 12, color: 'var(--muted)' }}>基础年化</div>
                        <div style={{ fontWeight: 700 }}>{token.baseYield}%</div>
                      </div>
                    </div>

                    <div style={{ marginTop: 10 }}>
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                        <div style={{ fontSize: 12, color: 'var(--muted)' }}>杠杆</div>
                        <div style={{ fontWeight: 700 }}>{L}x</div>
                      </div>
                      <input type="range" min="1" max="9" step="0.5" value={L} onChange={e => updateTokenLeverage(token.symbol, Number(e.target.value))} style={{ width: '100%', marginTop: 8 }} />
                    </div>

                    <div style={{ marginTop: 10, borderTop: '1px solid rgba(255,255,255,0.02)', paddingTop: 8 }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <div style={{ fontSize: 12, color: 'var(--muted)' }}>放大后收益 (Gross)</div>
                        <div style={{ fontWeight: 700 }}>{gross}%</div>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6 }}>
                        <div style={{ fontSize: 12, color: 'var(--muted)' }}>借款成本</div>
                        <div style={{ color: '#ff7b7b', fontWeight: 700 }}>{cost}%</div>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8 }}>
                        <div style={{ fontSize: 12, color: 'var(--muted)' }}>估计净收益</div>
                        <div style={{ color: net >= 0 ? '#7ee787' : '#ff8b8b', fontWeight: 900 }}>{net}%</div>
                      </div>

                      {/* 杠杆按钮 */}
                      <div style={{ marginTop: 10 }}>
                        <button onClick={() => createLoan(token)} disabled={!signer || loading} style={{ padding: '8px 10px', borderRadius: 8, background: 'linear-gradient(90deg,#f59e0b,#f97316)', color: 'white', border: 'none', cursor: 'pointer' }}>杠杆</button>
                      </div>
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        </div>
      )}

      {/* Loan creation modal/form */}
      {showLoanForm && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 2000 }}>
          <div style={{ background: 'white', color: 'black', padding: 18, borderRadius: 8, width: 420, maxWidth: '95%' }}>
            <h3 style={{ marginTop: 0 }}>创建杠杆贷款 — USDC → PT-sUSDE</h3>
            
            {/* 计算预览区域 */}
            {(() => {
              const principalNum = Number(loanPrincipalInput || '0')
              const L = Number(loanSelectedLeverage || 1)
              if (principalNum > 0 && L >= 1) {
                const debtNum = principalNum * (L - 1)
                const totalPositionValueUSDC = principalNum * L
                const requiredCollateralValueUSDC = debtNum / AAVE_LTV_LIMIT
                const collateralValueUSDC = Math.max(totalPositionValueUSDC, requiredCollateralValueUSDC)
                const collateralPT = collateralValueUSDC / PT_PRICE_USDC
                const currentRate = aaveRate == null ? simulatedAaveRate : aaveRate
                const grossYield = 14.0 * L // PT-sUSDE base yield * leverage
                const borrowCost = currentRate * (L - 1)
                const netYield = grossYield - borrowCost
                
                return (
                  <div style={{ background: '#f8f9fa', padding: 12, borderRadius: 6, marginBottom: 12 }}>
                    <div style={{ fontWeight: 700, marginBottom: 8, color: '#374151' }}>计算预览</div>
                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, fontSize: 13 }}>
                      <div>本金 (USDC): <strong>{principalNum.toFixed(2)}</strong></div>
                      <div>杠杆倍率: <strong>{L}x</strong></div>
                      <div>借款 (USDC): <strong>{debtNum.toFixed(2)}</strong></div>
                      <div>抵押 (PT): <strong>{collateralPT.toFixed(4)}</strong></div>
                      <div>抵押价值 (USDC): <strong>{collateralValueUSDC.toFixed(2)}</strong></div>
                      <div>总仓位价值 (USDC): <strong>{totalPositionValueUSDC.toFixed(2)}</strong></div>
                    </div>
                    <div style={{ borderTop: '1px solid #e5e7eb', paddingTop: 8, marginTop: 8 }}>
                      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8, fontSize: 13 }}>
                        <div style={{ textAlign: 'center' }}>
                          <div style={{ color: '#10b981', fontWeight: 700 }}>{grossYield.toFixed(2)}%</div>
                          <div style={{ color: '#6b7280' }}>放大收益</div>
                        </div>
                        <div style={{ textAlign: 'center' }}>
                          <div style={{ color: '#ef4444', fontWeight: 700 }}>{borrowCost.toFixed(2)}%</div>
                          <div style={{ color: '#6b7280' }}>借款成本</div>
                        </div>
                        <div style={{ textAlign: 'center' }}>
                          <div style={{ color: netYield >= 0 ? '#10b981' : '#ef4444', fontWeight: 700 }}>{netYield.toFixed(2)}%</div>
                          <div style={{ color: '#6b7280' }}>净收益</div>
                        </div>
                      </div>
                    </div>
                  </div>
                )
              }
              return null
            })()}

            {/* USDC 授权状态 */}
            <div style={{ marginBottom: 12, padding: 10, background: '#f0f9ff', borderRadius: 6, border: '1px solid #e0f2fe' }}>
              <div style={{ fontSize: 13, color: '#374151' }}>
                USDC 授权余额: <strong>{Number(principalAllowance).toFixed(2)}</strong>
                {Number(principalAllowance) < Number(loanPrincipalInput || '0') && (
                  <span style={{ color: '#ef4444', marginLeft: 8 }}>⚠️ 授权不足</span>
                )}
              </div>
              <button 
                onClick={approvePrincipal} 
                disabled={loanApproving || !loanPrincipalInput || Number(loanPrincipalInput) <= 0} 
                style={{ 
                  marginTop: 6, 
                  padding: '6px 12px', 
                  background: loanApproving ? '#9ca3af' : '#10b981', 
                  color: 'white', 
                  border: 'none', 
                  borderRadius: 4,
                  cursor: loanApproving ? 'not-allowed' : 'pointer',
                  fontSize: 12
                }}
              >
                {loanApproving ? '授权中...' : '授权 USDC'}
              </button>
            </div>

            <div style={{ marginBottom: 8 }}>
              <label>本金 (USDC)</label>
              <input 
                type="number" 
                value={loanPrincipalInput} 
                onChange={e => setLoanPrincipalInput(e.target.value)} 
                placeholder="输入本金数量" 
                style={{ width: '100%', marginTop: 6, padding: 8 }} 
              />
            </div>
            <div style={{ marginBottom: 8 }}>
              <label>杠杆倍率</label>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6 }}>
                <input 
                  type="range" 
                  min="1" 
                  max="9" 
                  step="0.5" 
                  value={loanSelectedLeverage} 
                  onChange={e => setLoanSelectedLeverage(Number(e.target.value))} 
                  style={{ flex: 1 }} 
                />
                <div style={{ fontWeight: 700, minWidth: 40 }}>{loanSelectedLeverage}x</div>
              </div>
            </div>
            <div style={{ marginBottom: 8 }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <input type="checkbox" checked={loanUseClosePrice} onChange={e => setLoanUseClosePrice(e.target.checked)} /> 设定平仓价格 (USDC / PT)
              </label>
              {loanUseClosePrice && (
                <input value={loanClosePriceInput} onChange={e => setLoanClosePriceInput(e.target.value)} placeholder="例如: 200 (表示 200 USDC 每 1 PT)" style={{ width: '100%', marginTop: 6, padding: 8 }} />
              )}
            </div>
            <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
              <div style={{ flex: 1 }}>
                <label>利率模式</label>
                <select value={loanInterestMode} onChange={e => setLoanInterestMode(Number(e.target.value))} style={{ width: '100%', padding: 8, marginTop: 6 }}>
                  <option value={1}>Stable (1)</option>
                  <option value={2}>Variable (2)</option>
                </select>
              </div>
            </div>
            <div style={{ marginBottom: 12 }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <input type="checkbox" checked={loanUseDeadlineDate} onChange={e => setLoanUseDeadlineDate(e.target.checked)} /> 设置具体的 Take 截止时间
              </label>
              {loanUseDeadlineDate && (
                <input type="datetime-local" value={loanDeadlineDatetime} onChange={e => setLoanDeadlineDatetime(e.target.value)} style={{ width: '100%', marginTop: 6, padding: 8 }} />
              )}
              <div style={{ fontSize: 12, color: '#6b7280', marginTop: 4 }}>
                ⚠️ 说明：deadline 限制其他人 take 您的仓位的截止时间，过期后其他人无法 take。您作为仓位所有者可随时平仓，不受此限制。
              </div>
            </div>
            {/* display computed expectProfit if close price enabled */}
            {loanUseClosePrice && loanClosePriceInput && (
              <div style={{ marginBottom: 12, color: '#374151' }}>
                预估 expectProfit: {(() => {
                  try {
                    const debtDecimals = 6
                    const collateralDecimals = 18
                    const coll = ethers.utils.parseUnits(loanPrincipalInput || '0', collateralDecimals)
                    const closePriceScaled = ethers.utils.parseUnits(loanClosePriceInput.trim(), debtDecimals)
                    const collateralScale = ethers.BigNumber.from(10).pow(collateralDecimals)
                    const valueInDebt = coll.mul(closePriceScaled).div(collateralScale)
                    const debt = ethers.utils.parseUnits(loanPrincipalInput || '0', debtDecimals)
                    const expectBN = valueInDebt.gt(debt) ? valueInDebt.sub(debt) : ethers.BigNumber.from(0)
                    return ethers.utils.formatUnits(expectBN, debtDecimals) + ' USDC'
                  } catch (e) {
                    return '—'
                  }
                })()}
              </div>
            )}
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
              <button onClick={cancelLoanForm} disabled={loanSubmitting} style={{ padding: '8px 12px' }}>取消</button>
              <button 
                onClick={submitCreateLoan} 
                disabled={loanSubmitting || Number(principalAllowance) < Number(loanPrincipalInput || '0')} 
                style={{ 
                  padding: '8px 12px', 
                  background: (loanSubmitting || Number(principalAllowance) < Number(loanPrincipalInput || '0')) ? '#9ca3af' : '#f59e0b', 
                  color: 'white', 
                  border: 'none',
                  cursor: (loanSubmitting || Number(principalAllowance) < Number(loanPrincipalInput || '0')) ? 'not-allowed' : 'pointer'
                }}
              >
                {loanSubmitting ? '提交中...' : '确认并提交'}
              </button>
            </div>
          </div>
        </div>
      )}

      {error && (
        <div style={{ marginTop: 16, color: '#ff8b8b' }}>错误: {error}</div>
      )}
    </div>
  )
}
