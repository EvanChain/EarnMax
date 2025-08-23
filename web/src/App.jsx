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

  const [routerAddr, setRouterAddr] = useState(DEPLOYMENTS.Router)
  const [userPivAddr, setUserPivAddr] = useState(null)
  const [deploying, setDeploying] = useState(false)
  const [diagInfo, setDiagInfo] = useState(null)

  // PIV contract used for quick 'leverage' action (fixed as requested)
  const PIV_FIXED_ADDR = '0x29D88ccDCD0326E05D8845A935CFCC1072c4084b'

  // Loan form state
  const [showLoanForm, setShowLoanForm] = useState(false)
  const [loanCollateralAmtInput, setLoanCollateralAmtInput] = useState('0.01')
  const [loanDebtAmtInput, setLoanDebtAmtInput] = useState('100')
  const [loanInterestMode, setLoanInterestMode] = useState(2)
  const [loanDeadlineHours, setLoanDeadlineHours] = useState(1)
  const [loanSubmitting, setLoanSubmitting] = useState(false)
  const [loanTargetTokenPair, setLoanTargetTokenPair] = useState({ from: null, to: null })
  const [loanUseDeadlineDate, setLoanUseDeadlineDate] = useState(false)
  const [loanDeadlineDatetime, setLoanDeadlineDatetime] = useState('') // ISO-like local datetime string
  const [loanUseClosePrice, setLoanUseClosePrice] = useState(false)
  const [loanClosePriceInput, setLoanClosePriceInput] = useState('')

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
    setLoanCollateralAmtInput('0.01')
    setLoanDebtAmtInput('100')
    setLoanInterestMode(2)
    setLoanDeadlineHours(1)
    setShowLoanForm(true)
  }

  async function submitCreateLoan() {
    if (!signer) {
      setError('请先连接钱包')
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

      // parse user inputs
      const collateralDecimals = 18
      const debtDecimals = 6
      const collateralAmount = ethers.utils.parseUnits(loanCollateralAmtInput || '0', collateralDecimals)
      const debtAmount = ethers.utils.parseUnits(loanDebtAmtInput || '0', debtDecimals)

      if (collateralAmount.lte(0) || debtAmount.lte(0)) {
        setError('请输入有效的抵押和借款金额')
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
      let deadlineTs = now + Number(loanDeadlineHours) * 3600
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

      const MOCK_SWAP_ADAPTER = '0x4de3ff522822292e64ece306CFdeE6f5009D3BB8'
      const swapData = ethers.utils.defaultAbiCoder.encode(['uint256'], [collateralAmount.toString()])
      const swapUnits = [
        {
          adapter: MOCK_SWAP_ADAPTER,
          tokenIn: loanTargetTokenPair.from,
          tokenOut: loanTargetTokenPair.to,
          swapData: swapData
        }
      ]

      const position = {
        collateralToken: loanTargetTokenPair.to,
        collateralAmount: collateralAmount.toString(),
        debtToken: loanTargetTokenPair.from,
        debtAmount: debtAmount.toString(),
        principal: '0',
        interestRateMode: loanInterestMode,
        expectProfit: expectProfitBN.toString(),
        deadline: deadlineTs
      }

      // submit tx
      const tx = await piv.createPosition(position, false, swapUnits)
      await tx.wait()
      setError('杠杆交易已提交（交易哈希: ' + tx.hash + '）')
      setShowLoanForm(false)
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

      {/* Dex-style header + token list */}
      <div style={{
        background: 'linear-gradient(90deg, rgba(124,58,237,0.12), rgba(59,130,246,0.06))',
        padding: 18,
        borderRadius: 12,
        marginBottom: 18
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <h1 style={{ margin: 0 }}>EarnMax</h1>
            <div style={{ color: 'var(--muted)', marginTop: 6 }}>快速查看多种资产在不同杠杆下的示例年化收益（模拟数据，仅供参考）。</div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ color: 'var(--muted)' }}>模拟 Aave 借出利率</div>
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

                    {/* 新增：杠杆按钮（调用固定 PIV 合约创建 loan） */}
                    <div style={{ marginTop: 10, display: 'flex', gap: 8 }}>
                      <button onClick={() => createLoan(token)} disabled={!signer || loading} style={{ padding: '8px 10px', borderRadius: 8, background: 'linear-gradient(90deg,#f59e0b,#f97316)', color: 'white', border: 'none', cursor: 'pointer' }}>杠杆</button>
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </div>

      {/* Loan creation modal/form */}
      {showLoanForm && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 2000 }}>
          <div style={{ background: 'white', color: 'black', padding: 18, borderRadius: 8, width: 420, maxWidth: '95%' }}>
            <h3 style={{ marginTop: 0 }}>创建杠杆贷款 — USDC → PT-sUSDE</h3>
            <div style={{ marginBottom: 8 }}>
              <label>抵押 (PT) 数量</label>
              <input value={loanCollateralAmtInput} onChange={e => setLoanCollateralAmtInput(e.target.value)} style={{ width: '100%', marginTop: 6, padding: 8 }} />
            </div>
            <div style={{ marginBottom: 8 }}>
              <label>借款 (USDC) 数量</label>
              <input value={loanDebtAmtInput} onChange={e => setLoanDebtAmtInput(e.target.value)} style={{ width: '100%', marginTop: 6, padding: 8 }} />
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
              <div style={{ width: 140 }}>
                <label>有效期 (小时)</label>
                <input type="number" value={loanDeadlineHours} onChange={e => setLoanDeadlineHours(Number(e.target.value))} style={{ width: '100%', padding: 8, marginTop: 6 }} />
              </div>
            </div>
            <div style={{ marginBottom: 12 }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <input type="checkbox" checked={loanUseDeadlineDate} onChange={e => setLoanUseDeadlineDate(e.target.checked)} /> 最晚到期时间
              </label>
              {loanUseDeadlineDate && (
                <input type="datetime-local" value={loanDeadlineDatetime} onChange={e => setLoanDeadlineDatetime(e.target.value)} style={{ width: '100%', marginTop: 6, padding: 8 }} />
              )}
            </div>
            {/* display computed expectProfit if close price enabled */}
            {loanUseClosePrice && loanClosePriceInput && (
              <div style={{ marginBottom: 12, color: '#374151' }}>
                预估 expectProfit: {(() => {
                  try {
                    const debtDecimals = 6
                    const collateralDecimals = 18
                    const coll = ethers.utils.parseUnits(loanCollateralAmtInput || '0', collateralDecimals)
                    const closePriceScaled = ethers.utils.parseUnits(loanClosePriceInput.trim(), debtDecimals)
                    const collateralScale = ethers.BigNumber.from(10).pow(collateralDecimals)
                    const valueInDebt = coll.mul(closePriceScaled).div(collateralScale)
                    const debt = ethers.utils.parseUnits(loanDebtAmtInput || '0', debtDecimals)
                    const expectBN = valueInDebt.gt(debt) ? valueInDebt.sub(debt) : ethers.BigNumber.from(0)
                    return ethers.utils.formatUnits(expectBN, debtDecimals) + ' USDC'
                  } catch (e) {
                    return '—'
                  }
                })()}</div>
            )}
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
              <button onClick={cancelLoanForm} disabled={loanSubmitting} style={{ padding: '8px 12px' }}>取消</button>
              <button onClick={submitCreateLoan} disabled={loanSubmitting} style={{ padding: '8px 12px', background: '#f59e0b', color: 'white', border: 'none' }}>{loanSubmitting ? '提交中...' : '确认并提交'}</button>
            </div>
          </div>
        </div>
      )}

      {/* ...existing UI (rest of the page) ... */}

      {/* original content preserved below */}
      <div style={{ marginBottom: 12 }}>
        {account ? (
          <div>已连接钱包: {account}</div>
        ) : (
          <button onClick={connectWallet}>连接 MetaMask</button>
        )}
      </div>

      <div style={{ marginBottom: 12, color: 'var(--muted)' }}>
        <label>Aave Pool 地址: </label>
        <input value={aavePool} onChange={e => setAavePool(e.target.value)} style={{ width: '70%' }} />
      </div>

      <div style={{ marginBottom: 12 }}>
        <label>
          <input type="checkbox" checked={simulateAave} onChange={e => setSimulateAave(e.target.checked)} /> 使用模拟 Aave 借出利率
        </label>
        {simulateAave && (
          <span style={{ marginLeft: 12 }}>
            模拟利率: <input type="number" step="0.01" value={simulatedAaveRate} onChange={e => setSimulatedAaveRate(Number(e.target.value))} style={{ width: 80 }} /> %
          </span>
        )}
      </div>

      <div style={{ marginBottom: 12 }}>
        <button onClick={fetchAaveBorrowRate} disabled={loading}>
          刷新 Aave 借款利率
        </button>
      </div>

      <div style={{ marginTop: 20, textAlign: 'left' }}>
        <h3>利率 (基础)</h3>
        <div>USDC 在 Aave 的 当前可变借款利率: {aaveRate == null ? '—' : `${aaveRate}%`}</div>
        <div style={{ marginTop: 8 }}>
          Pendle PT-sUSDE 的 基础年化收益率 (PT):
          <input
            value={pendleYield}
            onChange={e => setPendleYield(Number(e.target.value))}
            style={{ width: 100, marginLeft: 8 }}
            type="number"
            step="0.01"
          />
          %
        </div>
      </div>

      <div style={{ marginTop: 20, textAlign: 'left' }}>
        <h3>杠杆放大 (最多 9x)</h3>
        <div>
          <input
            type="range"
            min="1"
            max="9"
            step="0.1"
            value={leverage}
            onChange={e => setLeverage(Number(e.target.value))}
            style={{ width: '100%' }}
          />
          <div>当前杠杆: {leverage}x</div>
        </div>

        <div style={{ marginTop: 12 }}>
          <strong>放大后利率 (简单乘法放大示意)</strong>
          <div>借款利率 (Aave) 放大后: {amplifiedAave == null ? '—' : `${amplifiedAave}%`}</div>
          <div>Pendle PT 收益 放大后: {`${amplifiedPendle}%`}</div>

          <div style={{ marginTop: 12 }}>
            <h4>净放大收益示例</h4>
            <div>放大后 Pendle 收益 (Gross): {`${grossPendle}%`}</div>
            <div>放大后的借款成本 (Borrow cost): {`${totalBorrowCost}%`}</div>
            <div style={{ marginTop: 6, fontWeight: '600' }}>估计净收益 (Approx. net yield on equity): {`${netLeveragedYield}%`}</div>
            <div style={{ marginTop: 8, color: '#ffb86b' }}>
              风险提示：该计算为简化估算，未考虑手续费、借贷利率波动、清算风险与融资费用。实际策略更复杂，请谨慎评估风险。
            </div>
          </div>
        </div>
      </div>

      <div style={{ marginTop: 20, textAlign: 'left' }}>
        <h3>模拟 Pendle 市场数据（仅示例）</h3>
        <div style={{ marginBottom: 8 }}>
          <label>选择情景: </label>
          <select value={selectedScenario} onChange={e => setSelectedScenario(e.target.value)}>
            {PENDLE_SCENARIOS.map(s => (
              <option key={s.id} value={s.id}>{s.label}</option>
            ))}
          </select>
        </div>

        <div>
          <strong>模拟指标</strong>
          <div>PT 年化收益 (模拟): {PENDLE_SCENARIOS.find(x => x.id === selectedScenario).ptYield}%</div>
          <div>pt-sUSDE 年化收益 (模拟): {PENDLE_SCENARIOS.find(x => x.id === selectedScenario).ptSdsdeYield}%</div>
          <div style={{ marginTop: 8, color: 'var(--muted)' }}>
            说明：这些数据为本地模拟示例，不会访问 Pendle 合约。你可以在上方修改“Pendle PT 基础年化收益率”以进行自定义模拟。
          </div>
        </div>
      </div>

      <div style={{ marginTop: 20, textAlign: 'left' }}>
        <h3>测试合约交互（链上 Mock 合约）</h3>
        <div>Faucet 合约: {faucetAddr}</div>
        <div>MockUSDC 合约: {mockUSDCAddr || '加载中...'}</div>
        <div>Mock PT-sUSDE 合约: {mockPtAddr || '加载中...'}</div>

        <div style={{ marginTop: 12 }}>
          <button onClick={callFaucet} disabled={loading || !signer}>从 Faucet 获取测试代币 (faucet)</button>
          <button onClick={fetchTokenBalances} style={{ marginLeft: 12 }} disabled={loading || !account}>刷新代币余额</button>
        </div>

        <div style={{ marginTop: 12 }}>
          <div>账户余额:</div>
          <div>MockUSDC: {balances.mockUSDC == null ? '—' : balances.mockUSDC}</div>
          <div>Mock PT-sUSDE: {balances.mockPT == null ? '—' : balances.mockPT}</div>
        </div>
      </div>

      <div style={{ marginTop: 20, textAlign: 'left' }}>
        <h3>你的 PIV 合约</h3>
        <div>Router 合约: {routerAddr}</div>
        <div style={{ marginTop: 8 }}>
          {userPivAddr ? (
            <div>
              已存在 PIV: <a href={`https://etherscan.io/address/${userPivAddr}`} target="_blank" rel="noreferrer">{userPivAddr}</a>
              <div style={{ marginTop: 6 }}>
                <button onClick={fetchUserPiv} disabled={loading}>刷新 PIV 地址</button>
              </div>
            </div>
          ) : (
            <div>
              未检测到 PIV 合约
              <div style={{ marginTop: 8 }}>
                <button onClick={deployPivOnChain} disabled={deploying || !signer}>在链上创建 PIV (调用 Router.deployPIV)</button>
                <button onClick={fetchUserPiv} style={{ marginLeft: 12 }} disabled={loading}>刷新</button>
                <button onClick={diagnosePivMapping} style={{ marginLeft: 12 }} disabled={loading}>诊断 PIV 映射</button>
              </div>
              <div style={{ marginTop: 8, color: 'var(--muted)' }}>
                注意：部署会发起链上交易，需要支付矿工费，且会将你的地址作为 PIV 的所有者。
              </div>
            </div>
          )}
        </div>
        {diagInfo && (
          <div style={{ marginTop: 12, background: 'rgba(255,255,255,0.01)', padding: 10, borderRadius: 8 }}>
            <div style={{ fontSize: 13, fontWeight: 700 }}>诊断信息</div>
            <div>chainId: {diagInfo.chainId}</div>
            <div>Router 合约代码存在: {diagInfo.routerCode && diagInfo.routerCode !== '0x' ? '是' : '否'}</div>
            <div>userPivMapping: {diagInfo.mapping || '无映射 (null)'}</div>
            <div style={{ marginTop: 6 }}>最近 PIVDeployed 事件: {diagInfo.events.length}</div>
            <div style={{ fontSize: 12, color: 'var(--muted)', marginTop: 6 }}>
              说明：若 Router 合约代码为空或 chainId 不正确，请检查钱包网络是否与部署网络一致；若 events 中存在你地址对应的 owner，则可参考事件返回的 piv 地址。
            </div>
          </div>
        )}
      </div>

      {error && (
        <div style={{ marginTop: 16, color: '#ff8b8b' }}>错误: {error}</div>
      )}

      <p style={{ marginTop: 18, color: 'var(--muted)' }}>
        说明: 本页面从指定的 Aave Pool 获取 USDC 的当前可变借款利率 (若 Aave 使用 Ray 单位，则会按 1e27 转换为年化比例)。Pendle 的 PT 收益需手动填写。杠杆放大采用简单乘法进行示意计算，实际杠杆策略需考虑借款成本、费用与清算风险。
      </p>
    </div>
  )
}
