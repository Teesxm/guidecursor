import { useEffect, useMemo, useState } from 'react'
import {
  AnimatePresence,
  animate,
  motion,
  useMotionValue,
  useReducedMotion,
  useSpring,
  useTransform,
} from 'motion/react'
import {
  ArrowLeft,
  ArrowRight,
  BarChart3,
  BriefcaseBusiness,
  Check,
  ChevronRight,
  CircleDollarSign,
  Compass,
  Gauge,
  Lightbulb,
  LineChart,
  MousePointer2,
  RotateCcw,
  Search,
  Sparkles,
  Target,
  Timer,
  Users,
  X,
  Zap,
} from 'lucide-react'
import { onboardingQuestions, roleProfiles, tasks, type Trait } from './data'
import { AnimatedNumber, MotionCheck, ScoreRing, gentleSpring, softSpring } from './motion'

type Screen = 'landing' | 'onboarding' | 'swipe' | 'bridge' | 'simulation' | 'results'
type SimulationAnswer = 'conversion' | 'traffic' | 'order-value' | null

const traitLabels: Record<Trait, string> = {
  analytical: 'Analytical thinking',
  creative: 'Creativity',
  social: 'People interaction',
  structured: 'Structured work',
  autonomy: 'Autonomy',
  decision: 'Decision-making',
}

const traitDescriptions: Record<Trait, string> = {
  analytical: 'You repeatedly chose work that involves evidence, patterns and diagnosis.',
  creative: 'You showed interest in shaping ideas and finding less obvious approaches.',
  social: 'You were drawn to situations that involve clients, teams or influencing others.',
  structured: 'You preferred tasks with clear systems, processes and measurable progress.',
  autonomy: 'You responded well to work where you can shape your own route to an answer.',
  decision: 'You showed comfort making calls when the information is incomplete.',
}

const metrics = [
  {
    id: 'conversion',
    label: 'Conversion rate',
    value: '2.4%',
    delta: '−37%',
    tone: 'alert',
    detail: 'Conversion fell from 3.8% to 2.4%, with the largest drop happening on mobile checkout.',
  },
  {
    id: 'traffic',
    label: 'Website traffic',
    value: '1.24m',
    delta: '+4%',
    tone: 'good',
    detail: 'Traffic is slightly higher than last quarter and channel mix is broadly unchanged.',
  },
  {
    id: 'order-value',
    label: 'Avg. order value',
    value: '€64.20',
    delta: '−2%',
    tone: 'neutral',
    detail: 'Average order value is nearly flat and does not explain most of the revenue decline.',
  },
  {
    id: 'returns',
    label: 'Return rate',
    value: '8.1%',
    delta: '+1%',
    tone: 'neutral',
    detail: 'Returns increased slightly, mainly in one apparel category, but the financial effect is limited.',
  },
]

const screenTransition = {
  duration: 0.34,
  ease: [0.22, 0.8, 0.24, 1] as const,
}

function App() {
  const reducedMotion = useReducedMotion()
  const [screen, setScreen] = useState<Screen>('landing')
  const [onboardingIndex, setOnboardingIndex] = useState(0)
  const [preferences, setPreferences] = useState<Trait[]>([])
  const [taskIndex, setTaskIndex] = useState(0)
  const [likedTasks, setLikedTasks] = useState<number[]>([])
  const [taskDirection, setTaskDirection] = useState<'left' | 'right' | null>(null)
  const [reveal, setReveal] = useState<string | null>(null)
  const [inspected, setInspected] = useState<string[]>([])
  const [activeMetric, setActiveMetric] = useState<string | null>(null)
  const [simulationAnswer, setSimulationAnswer] = useState<SimulationAnswer>(null)
  const [simulationDone, setSimulationDone] = useState(false)

  const reset = () => {
    setScreen('landing')
    setOnboardingIndex(0)
    setPreferences([])
    setTaskIndex(0)
    setLikedTasks([])
    setTaskDirection(null)
    setReveal(null)
    setInspected([])
    setActiveMetric(null)
    setSimulationAnswer(null)
    setSimulationDone(false)
  }

  const pickPreference = (trait: Trait) => {
    setPreferences((current) => [...current, trait])
    if (onboardingIndex === onboardingQuestions.length - 1) {
      window.setTimeout(() => setScreen('swipe'), reducedMotion ? 0 : 180)
      return
    }
    setOnboardingIndex((index) => index + 1)
  }

  const chooseTask = (interested: boolean) => {
    if (taskDirection) return
    const current = tasks[taskIndex]

    setTaskDirection(interested ? 'right' : 'left')
    if (interested) setLikedTasks((items) => [...items, current.id])
    setReveal(current.reveal)

    window.setTimeout(() => {
      setTaskDirection(null)
      setReveal(null)
      if (taskIndex === tasks.length - 1) {
        setScreen('bridge')
      } else {
        setTaskIndex((index) => index + 1)
      }
    }, reducedMotion ? 220 : 720)
  }

  useEffect(() => {
    window.scrollTo({ top: 0, behavior: reducedMotion ? 'auto' : 'smooth' })
  }, [screen, reducedMotion])

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (screen !== 'swipe' || taskDirection) return
      if (event.key === 'ArrowLeft') chooseTask(false)
      if (event.key === 'ArrowRight') chooseTask(true)
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  })

  const inspectMetric = (id: string) => {
    setActiveMetric(id)
    setInspected((items) => (items.includes(id) ? items : [...items, id]))
  }

  const traitScores = useMemo(() => {
    const scores: Record<Trait, number> = {
      analytical: 48,
      creative: 46,
      social: 47,
      structured: 50,
      autonomy: 49,
      decision: 48,
    }

    preferences.forEach((trait) => {
      scores[trait] += 10
    })

    likedTasks.forEach((taskId) => {
      const task = tasks.find((item) => item.id === taskId)
      task?.traits.forEach((trait) => {
        scores[trait] += 5
      })
    })

    if (simulationDone) {
      scores.analytical += simulationAnswer === 'conversion' ? 11 : 5
      scores.decision += simulationAnswer === 'conversion' ? 8 : 4
      scores.structured += inspected.length >= 3 ? 7 : 3
      scores.autonomy += inspected[0] === 'conversion' ? 4 : 2
    }

    Object.keys(scores).forEach((key) => {
      const trait = key as Trait
      scores[trait] = Math.min(96, Math.max(38, scores[trait]))
    })

    return scores
  }, [preferences, likedTasks, simulationAnswer, simulationDone, inspected])

  const matches = useMemo(() => {
    return roleProfiles
      .map((role) => {
        const traitAverage =
          role.traits.reduce((sum, trait) => sum + traitScores[trait], 0) / role.traits.length
        const simulationLift =
          simulationDone && simulationAnswer === 'conversion' && role.title.includes('Analyst') ? 4 : 0
        return {
          ...role,
          score: Math.min(96, Math.round(role.base + (traitAverage - 55) * 0.28 + simulationLift)),
        }
      })
      .sort((a, b) => b.score - a.score)
  }, [traitScores, simulationDone, simulationAnswer])

  const currentMetric = metrics.find((metric) => metric.id === activeMetric)
  const stage =
    screen === 'onboarding' || screen === 'swipe'
      ? 0
      : screen === 'bridge'
        ? 1
        : screen === 'simulation'
          ? 2
          : 3

  const pageMotion = reducedMotion
    ? {}
    : {
        initial: { opacity: 0, y: 14, filter: 'blur(7px)' },
        animate: { opacity: 1, y: 0, filter: 'blur(0px)' },
        exit: { opacity: 0, y: -8, filter: 'blur(5px)' },
        transition: screenTransition,
      }

  return (
    <div className="app-shell">
      <div className="global-grain" aria-hidden="true" />
      {screen !== 'landing' && <AppHeader stage={stage} onReset={reset} />}

      <AnimatePresence mode="wait" initial={false}>
        <motion.div key={screen} {...pageMotion}>
          {screen === 'landing' && <Landing onStart={() => setScreen('onboarding')} />}

          {screen !== 'landing' && (
            <main className="experience-shell">
              {screen === 'onboarding' && (
                <Onboarding
                  index={onboardingIndex}
                  preferences={preferences}
                  onPick={pickPreference}
                  onBack={() => {
                    if (onboardingIndex === 0) {
                      setScreen('landing')
                      return
                    }
                    setPreferences((items) => items.slice(0, -1))
                    setOnboardingIndex((index) => index - 1)
                  }}
                />
              )}

              {screen === 'swipe' && (
                <TaskSwipe
                  taskIndex={taskIndex}
                  direction={taskDirection}
                  reveal={reveal}
                  onChoose={chooseTask}
                />
              )}

              {screen === 'bridge' && (
                <PreferenceBridge
                  preferences={preferences}
                  likedCount={likedTasks.length}
                  onContinue={() => setScreen('simulation')}
                />
              )}

              {screen === 'simulation' && (
                <Simulation
                  inspected={inspected}
                  activeMetric={activeMetric}
                  currentMetric={currentMetric}
                  answer={simulationAnswer}
                  done={simulationDone}
                  onInspect={inspectMetric}
                  onAnswer={setSimulationAnswer}
                  onComplete={() => setSimulationDone(true)}
                  onResults={() => setScreen('results')}
                />
              )}

              {screen === 'results' && (
                <Results
                  traitScores={traitScores}
                  matches={matches}
                  onReset={reset}
                  likedCount={likedTasks.length}
                />
              )}
            </main>
          )}
        </motion.div>
      </AnimatePresence>
    </div>
  )
}

function Brand() {
  return (
    <div className="brand">
      <div className="brand-mark">
        <Compass size={19} strokeWidth={2.4} />
      </div>
      <span>RoleQuest</span>
    </div>
  )
}

function Landing({ onStart }: { onStart: () => void }) {
  const reducedMotion = useReducedMotion()

  const container = {
    hidden: {},
    show: {
      transition: { staggerChildren: reducedMotion ? 0 : 0.09, delayChildren: reducedMotion ? 0 : 0.08 },
    },
  }

  const item = {
    hidden: reducedMotion ? { opacity: 1, y: 0 } : { opacity: 0, y: 18 },
    show: {
      opacity: 1,
      y: 0,
      transition: reducedMotion
        ? { duration: 0 }
        : { duration: 0.48, ease: [0.2, 0.8, 0.2, 1] as const },
    },
  }

  return (
    <main className="landing">
      <nav className="landing-nav">
        <Brand />
        <motion.div
          className="nav-note"
          initial={reducedMotion ? false : { opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.45 }}
        >
          Career discovery, rebuilt
        </motion.div>
        <motion.button
          className="nav-cta arrow-button"
          onClick={onStart}
          whileHover={reducedMotion ? undefined : { y: -1 }}
          whileTap={reducedMotion ? undefined : { scale: 0.97 }}
        >
          Try the experience <ArrowRight size={16} />
        </motion.button>
      </nav>

      <section className="hero">
        <motion.div className="hero-copy" variants={container} initial="hidden" animate="show">
          <motion.div className="eyebrow-pill" variants={item}>
            <Sparkles size={14} /> Built for people still figuring it out
          </motion.div>
          <motion.h1 variants={item}>
            Don't just read the job.
            <span> Experience it.</span>
          </motion.h1>
          <motion.p className="hero-lede" variants={item}>
            Discover careers through the work you'd actually be doing. Explore realistic tasks, try a short
            simulation and build your personal Role DNA.
          </motion.p>

          <motion.div className="hero-actions" variants={item}>
            <motion.button
              className="primary-button large arrow-button"
              onClick={onStart}
              whileHover={reducedMotion ? undefined : { y: -3, scale: 1.01 }}
              whileTap={reducedMotion ? undefined : { scale: 0.97 }}
              transition={softSpring}
            >
              Start discovering <ArrowRight size={18} />
            </motion.button>
            <div className="time-note">
              <Timer size={17} />
              <span>
                <strong>3 minute demo</strong>
                No CV required
              </span>
            </div>
          </motion.div>

          <motion.div className="journey-row" variants={item}>
            {[
              ['01', 'Explore'],
              ['02', 'Experience'],
              ['03', 'Prove'],
              ['04', 'Match'],
            ].map(([number, label], index) => (
              <motion.div
                className="journey-item"
                key={label}
                initial={reducedMotion ? false : { opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: reducedMotion ? 0 : 0.58 + index * 0.11 }}
              >
                <span>{number}</span>
                <strong>{label}</strong>
                {index < 3 && (
                  <div className="journey-link">
                    <ChevronRight size={14} />
                    <motion.i
                      initial={reducedMotion ? false : { scaleX: 0 }}
                      animate={{ scaleX: 1 }}
                      transition={{ delay: 0.66 + index * 0.11, duration: 0.34 }}
                    />
                  </div>
                )}
              </motion.div>
            ))}
          </motion.div>
        </motion.div>

        <HeroDemo />
      </section>

      <motion.section
        className="proof-strip"
        initial={reducedMotion ? false : { opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: reducedMotion ? 0 : 0.72, duration: 0.5 }}
      >
        <div>
          <span className="strip-label">Traditional job search</span>
          <strong>Search → Read → Apply → Interview</strong>
        </div>
        <div className="strip-divider" />
        <div>
          <span className="strip-label accent">RoleQuest</span>
          <strong>Task → Experience → Skill evidence → Match</strong>
        </div>
      </motion.section>
    </main>
  )
}

function HeroDemo() {
  const reducedMotion = useReducedMotion()
  const mx = useMotionValue(0)
  const my = useMotionValue(0)
  const rawRotateY = useTransform(mx, [-0.5, 0.5], [-4.5, 4.5])
  const rawRotateX = useTransform(my, [-0.5, 0.5], [4, -4])
  const rotateY = useSpring(rawRotateY, { stiffness: 110, damping: 20 })
  const rotateX = useSpring(rawRotateX, { stiffness: 110, damping: 20 })

  const handleMove = (event: React.MouseEvent<HTMLDivElement>) => {
    if (reducedMotion) return
    const rect = event.currentTarget.getBoundingClientRect()
    mx.set((event.clientX - rect.left) / rect.width - 0.5)
    my.set((event.clientY - rect.top) / rect.height - 0.5)
  }

  const resetTilt = () => {
    mx.set(0)
    my.set(0)
  }

  return (
    <motion.div
      className="hero-visual"
      initial={reducedMotion ? false : { opacity: 0, scale: 0.96, y: 18 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      transition={{ delay: reducedMotion ? 0 : 0.24, duration: 0.62, ease: [0.2, 0.8, 0.2, 1] }}
      onMouseMove={handleMove}
      onMouseLeave={resetTilt}
    >
      <motion.div
        className="ambient-orb orb-one"
        animate={
          reducedMotion
            ? undefined
            : { x: [0, 20, -12, 0], y: [0, -16, 10, 0], scale: [1, 1.05, 0.98, 1] }
        }
        transition={{ duration: 13, repeat: Infinity, ease: 'easeInOut' }}
      />
      <motion.div
        className="ambient-orb orb-two"
        animate={reducedMotion ? undefined : { x: [0, -18, 12, 0], y: [0, 14, -8, 0] }}
        transition={{ duration: 15, repeat: Infinity, ease: 'easeInOut' }}
      />

      <motion.div
        className="demo-window"
        style={reducedMotion ? undefined : { rotateX, rotateY, transformPerspective: 1100 }}
      >
        <div className="demo-toolbar">
          <div className="window-dots"><span /><span /><span /></div>
          <span>Task discovery</span>
          <span className="mini-counter">4 of 8</span>
        </div>
        <div className="preview-image">
          <img
            src="https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?auto=format&fit=crop&w=1200&q=85"
            alt="Team working in a modern office"
          />
          <div className="preview-tag">Market question</div>
        </div>
        <div className="preview-copy">
          <span className="preview-context">Wednesday, 14:20 · International expansion</span>
          <h3>Your company is considering entering a new European market.</h3>
          <p>Would you enjoy comparing demand, competitors and economics before recommending what to do next?</p>
        </div>
        <div className="preview-actions">
          <div className="preview-action no"><X size={19} /> Not for me</div>
          <div className="preview-action yes">Interested <ArrowRight size={19} /></div>
        </div>
        <div className="demo-sheen" aria-hidden="true" />
      </motion.div>

      <motion.div
        className="floating-card role-card"
        animate={reducedMotion ? undefined : { y: [0, -9, 0], rotate: [4, 5.5, 4] }}
        transition={{ duration: 5, repeat: Infinity, ease: 'easeInOut' }}
      >
        <span className="card-kicker">Role match</span>
        <div className="match-score">91%</div>
        <strong>Business Analyst</strong>
        <small>Strong analytical + structured fit</small>
      </motion.div>

      <motion.div
        className="floating-card dna-card"
        animate={reducedMotion ? undefined : { y: [0, 8, 0], rotate: [-4, -5, -4] }}
        transition={{ duration: 5.8, repeat: Infinity, ease: 'easeInOut', delay: 0.3 }}
      >
        <Target size={18} />
        <div>
          <span className="card-kicker">Role DNA</span>
          <strong>Analytical 88</strong>
        </div>
      </motion.div>
    </motion.div>
  )
}

function AppHeader({ stage, onReset }: { stage: number; onReset: () => void }) {
  const reducedMotion = useReducedMotion()
  const stages = ['Explore', 'Experience', 'Prove', 'Match']

  return (
    <motion.header
      className="app-header"
      initial={reducedMotion ? false : { y: -18, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.35 }}
    >
      <Brand />
      <div className="stage-nav">
        {stages.map((item, index) => (
          <motion.div
            layout={!reducedMotion}
            className={'stage-item ' + (index <= stage ? 'active' : '') + (index === stage ? ' current' : '')}
            key={item}
          >
            <motion.span
              animate={index === stage && !reducedMotion ? { scale: [1, 1.08, 1] } : undefined}
              transition={{ duration: 0.45 }}
            >
              {index + 1}
            </motion.span>
            <strong>{item}</strong>
          </motion.div>
        ))}
      </div>
      <motion.button
        className="icon-button restart-button"
        onClick={onReset}
        title="Restart demo"
        whileHover={reducedMotion ? undefined : { rotate: -45, scale: 1.05 }}
        whileTap={reducedMotion ? undefined : { scale: 0.9 }}
      >
        <RotateCcw size={17} />
      </motion.button>
    </motion.header>
  )
}

function Onboarding({
  index,
  preferences,
  onPick,
  onBack,
}: {
  index: number
  preferences: Trait[]
  onPick: (trait: Trait) => void
  onBack: () => void
}) {
  const reducedMotion = useReducedMotion()
  const [selected, setSelected] = useState<Trait | null>(null)
  const question = onboardingQuestions[index]
  const progress = ((index + 1) / onboardingQuestions.length) * 100

  useEffect(() => setSelected(null), [index])

  const choose = (trait: Trait) => {
    if (selected) return
    setSelected(trait)
    window.setTimeout(() => onPick(trait), reducedMotion ? 0 : 230)
  }

  const iconFor = (side: 'left' | 'right') => {
    if (side === 'left') {
      return index === 0 ? <BarChart3 /> : index === 1 ? <Target /> : index === 2 ? <Gauge /> : index === 3 ? <Search /> : <LineChart />
    }
    return index === 0 ? <Lightbulb /> : index === 1 ? <Users /> : index === 2 ? <Compass /> : index === 3 ? <Zap /> : <Gauge />
  }

  return (
    <section className="onboarding-screen screen-width">
      <div className="section-topline">
        <motion.button className="back-link" onClick={onBack} whileTap={reducedMotion ? undefined : { scale: 0.96 }}>
          <ArrowLeft size={16} /> Back
        </motion.button>
        <span>{index + 1} / {onboardingQuestions.length}</span>
      </div>

      <div className="thin-progress">
        <motion.div
          initial={false}
          animate={{ width: progress + '%' }}
          transition={reducedMotion ? { duration: 0 } : gentleSpring}
        />
      </div>

      <AnimatePresence mode="wait" initial={false}>
        <motion.div
          key={index}
          className="onboarding-content"
          initial={reducedMotion ? false : { opacity: 0, x: 24, filter: 'blur(5px)' }}
          animate={{ opacity: 1, x: 0, filter: 'blur(0px)' }}
          exit={reducedMotion ? undefined : { opacity: 0, x: -22, filter: 'blur(4px)' }}
          transition={{ duration: reducedMotion ? 0 : 0.32 }}
        >
          <span className="section-eyebrow">{question.eyebrow}</span>
          <h2>{question.question}</h2>
          <p>Go with your first reaction. There are no right answers.</p>

          <div className="preference-grid">
            {[
              { side: 'left' as const, option: question.left },
              { side: 'right' as const, option: question.right },
            ].map(({ side, option }, optionIndex) => (
              <div className="preference-option-wrap" key={side}>
                {optionIndex === 1 && <div className="or-divider mobile-or"><span>OR</span></div>}
                <motion.button
                  onClick={() => choose(option.trait)}
                  className={
                    'preference-card ' +
                    (selected === option.trait ? 'chosen ' : '') +
                    (selected && selected !== option.trait ? 'deemphasized' : '')
                  }
                  whileHover={selected || reducedMotion ? undefined : { y: -6, scale: 1.012 }}
                  whileTap={selected || reducedMotion ? undefined : { scale: 0.97 }}
                  animate={selected === option.trait && !reducedMotion ? { scale: [1, 0.97, 1.02, 1] } : undefined}
                  transition={softSpring}
                >
                  <motion.div
                    className={'preference-icon ' + (side === 'right' ? 'alt' : '')}
                    animate={
                      selected === option.trait && !reducedMotion
                        ? { rotate: [0, -5, 6, 0], scale: [1, 1.08, 1] }
                        : undefined
                    }
                  >
                    {iconFor(side)}
                  </motion.div>
                  <strong>{option.label}</strong>
                  <span>{selected === option.trait ? 'Selected' : 'Choose this'}</span>
                  <AnimatePresence>
                    {selected === option.trait && <MotionCheck />}
                  </AnimatePresence>
                </motion.button>
                {optionIndex === 0 && <div className="or-divider desktop-or"><span>OR</span></div>}
              </div>
            ))}
          </div>

          <div className="signal-note">
            <Sparkles size={16} />
            <span>These choices give RoleQuest a starting signal. Your task choices and simulation behaviour will refine it.</span>
          </div>
        </motion.div>
      </AnimatePresence>

      <div className="preference-history">
        <AnimatePresence>
          {preferences.map((trait, itemIndex) => (
            <motion.span
              key={trait + itemIndex}
              initial={reducedMotion ? false : { opacity: 0, scale: 0.75, y: 5 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={reducedMotion ? undefined : { opacity: 0, scale: 0.8 }}
              transition={softSpring}
            >
              <Check size={12} /> {traitLabels[trait]}
            </motion.span>
          ))}
        </AnimatePresence>
      </div>
    </section>
  )
}

function TaskSwipe({
  taskIndex,
  direction,
  reveal,
  onChoose,
}: {
  taskIndex: number
  direction: 'left' | 'right' | null
  reveal: string | null
  onChoose: (interested: boolean) => void
}) {
  const reducedMotion = useReducedMotion()
  const task = tasks[taskIndex]
  const nextTask = tasks[taskIndex + 1]
  const progress = ((taskIndex + 1) / tasks.length) * 100
  const x = useMotionValue(0)
  const rotate = useTransform(x, [-260, 0, 260], [-10, 0, 10])
  const yesOpacity = useTransform(x, [35, 125], [0, 1])
  const noOpacity = useTransform(x, [-125, -35], [1, 0])
  const nextScale = useTransform(x, [-220, 0, 220], [1, 0.965, 1])
  const nextY = useTransform(x, [-220, 0, 220], [0, 15, 0])
  const glowOpacity = useTransform(x, [-180, 0, 180], [0.38, 0, 0.38])
  const [committed, setCommitted] = useState<'left' | 'right' | null>(null)

  useEffect(() => {
    x.set(0)
    setCommitted(null)
  }, [taskIndex, x])

  const commitChoice = (interested: boolean) => {
    if (committed || direction) return
    const nextDirection = interested ? 'right' : 'left'
    setCommitted(nextDirection)

    if (!reducedMotion) {
      animate(x, interested ? 880 : -880, {
        duration: 0.43,
        ease: [0.2, 0.75, 0.2, 1],
      })
    }

    onChoose(interested)
  }

  return (
    <section className="swipe-screen">
      <div className="swipe-heading">
        <motion.div
          initial={reducedMotion ? false : { opacity: 0, x: -16 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.4 }}
        >
          <span className="section-eyebrow">Task discovery</span>
          <h2>Forget the job title for a minute.</h2>
          <p>React to the work itself. What would you actually want to spend time doing?</p>
        </motion.div>
        <div className="task-progress">
          <span>{taskIndex + 1} of {tasks.length}</span>
          <div className="thin-progress">
            <motion.div
              animate={{ width: progress + '%' }}
              transition={reducedMotion ? { duration: 0 } : gentleSpring}
            />
          </div>
        </div>
      </div>

      <div className="card-stage">
        <motion.div className="swipe-glow" style={{ opacity: glowOpacity }} />

        {nextTask && (
          <motion.div
            className="task-card next-card"
            aria-hidden="true"
            style={reducedMotion ? undefined : { scale: nextScale, y: nextY }}
          >
            <img src={nextTask.image} alt="" />
          </motion.div>
        )}

        <motion.article
          key={task.id}
          className="task-card active-card draggable-card"
          style={reducedMotion ? undefined : { x, rotate }}
          drag={reducedMotion ? false : 'x'}
          dragConstraints={{ left: 0, right: 0 }}
          dragElastic={0.72}
          dragMomentum={false}
          onDragEnd={(_, info) => {
            if (info.offset.x > 115 || info.velocity.x > 650) commitChoice(true)
            else if (info.offset.x < -115 || info.velocity.x < -650) commitChoice(false)
            else animate(x, 0, { type: 'spring', stiffness: 360, damping: 27 })
          }}
          whileTap={reducedMotion ? undefined : { cursor: 'grabbing' }}
        >
          <motion.div className="swipe-stamp stamp-no" style={{ opacity: noOpacity }}>
            <X size={18} /> NOT FOR ME
          </motion.div>
          <motion.div className="swipe-stamp stamp-yes" style={{ opacity: yesOpacity }}>
            INTERESTED <Check size={18} />
          </motion.div>

          <div className="task-photo">
            <img src={task.image} alt="Workplace setting" draggable={false} />
            <div className="photo-overlay" />
            <span className="task-category">{task.category}</span>
            <span className="task-number">Task {String(taskIndex + 1).padStart(2, '0')}</span>
          </div>

          <div className="task-body">
            <span className="task-context">{task.context}</span>
            <h3>{task.prompt}</h3>
            <p>{task.detail}</p>

            <div className="task-question">
              <Sparkles size={16} />
              <strong>Would you enjoy taking this on?</strong>
            </div>
          </div>

          <div className="task-actions">
            <motion.button
              className="choice-button reject"
              onClick={() => commitChoice(false)}
              whileHover={reducedMotion ? undefined : { y: -2 }}
              whileTap={reducedMotion ? undefined : { scale: 0.97 }}
            >
              <span className="choice-icon"><X size={21} /></span>
              <span><strong>Not for me</strong><small>← left arrow</small></span>
            </motion.button>
            <motion.button
              className="choice-button accept arrow-button"
              onClick={() => commitChoice(true)}
              whileHover={reducedMotion ? undefined : { y: -2 }}
              whileTap={reducedMotion ? undefined : { scale: 0.97 }}
            >
              <span><strong>Interested</strong><small>right arrow →</small></span>
              <span className="choice-icon"><ArrowRight size={21} /></span>
            </motion.button>
          </div>
        </motion.article>

        <AnimatePresence>
          {reveal && (
            <motion.div
              className={'signal-captured ' + (direction === 'right' ? 'positive' : 'neutral')}
              initial={reducedMotion ? false : { opacity: 0, y: 18, scale: 0.94 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={reducedMotion ? undefined : { opacity: 0, y: -10, scale: 0.98 }}
              transition={softSpring}
            >
              <div className="signal-captured-icon">
                {direction === 'right' ? <Check size={17} /> : <X size={17} />}
              </div>
              <div>
                <strong>{direction === 'right' ? 'Preference signal captured' : 'Got it - not your thing'}</strong>
                <span>{reveal}</span>
              </div>
              {direction === 'right' && (
                <div className="signal-traits">
                  {task.traits.slice(0, 2).map((trait) => <span key={trait}>+ {traitLabels[trait]}</span>)}
                </div>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <div className="swipe-help">
        <MousePointer2 size={14} />
        <span>Drag the card, use the buttons or press your arrow keys</span>
      </div>
    </section>
  )
}

function PreferenceBridge({
  preferences,
  likedCount,
  onContinue,
}: {
  preferences: Trait[]
  likedCount: number
  onContinue: () => void
}) {
  const reducedMotion = useReducedMotion()
  const uniquePreferences = Array.from(new Set(preferences)).slice(0, 3)
  const previewTraits = uniquePreferences.length >= 3
    ? uniquePreferences
    : (['analytical', 'decision', 'structured'] as Trait[]).slice(0, 3)

  return (
    <section className="bridge-screen screen-width">
      <motion.div
        className="bridge-orb"
        animate={reducedMotion ? undefined : { scale: [1, 1.08, 1], opacity: [0.55, 0.78, 0.55] }}
        transition={{ duration: 4, repeat: Infinity, ease: 'easeInOut' }}
      />
      <motion.div
        className="bridge-content"
        initial={reducedMotion ? false : { opacity: 0, y: 22 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
      >
        <motion.div
          className="bridge-icon"
          initial={reducedMotion ? false : { scale: 0.6, rotate: -20 }}
          animate={{ scale: 1, rotate: 0 }}
          transition={softSpring}
        >
          <Target size={26} />
        </motion.div>
        <span className="section-eyebrow">Preference signal complete</span>
        <h2>Your preferences are taking shape.</h2>
        <p>
          You reacted to {tasks.length} realistic work situations and marked {likedCount} as interesting.
          That tells us what pulls you in. Now we want to see how you approach the work.
        </p>

        <div className="bridge-dna">
          {previewTraits.map((trait, index) => {
            const widths = [84, 72, 65]
            return (
              <motion.div
                className="bridge-trait"
                key={trait}
                initial={reducedMotion ? false : { opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: reducedMotion ? 0 : 0.18 + index * 0.1 }}
              >
                <div><span>{traitLabels[trait]}</span><small>emerging signal</small></div>
                <div className="bridge-track">
                  <motion.div
                    initial={reducedMotion ? false : { width: 0 }}
                    animate={{ width: widths[index] + '%' }}
                    transition={{ delay: reducedMotion ? 0 : 0.3 + index * 0.1, duration: 0.7 }}
                  />
                </div>
              </motion.div>
            )
          })}
        </div>

        <div className="bridge-separator"><span>Preference</span><i /><span>Behaviour</span></div>

        <motion.button
          className="primary-button large arrow-button"
          onClick={onContinue}
          whileHover={reducedMotion ? undefined : { y: -3, scale: 1.01 }}
          whileTap={reducedMotion ? undefined : { scale: 0.97 }}
        >
          Begin micro-simulation <ArrowRight size={18} />
        </motion.button>
        <small className="bridge-note">Next: a 2 minute Business Analysis challenge</small>
      </motion.div>
    </section>
  )
}

function Simulation({
  inspected,
  activeMetric,
  currentMetric,
  answer,
  done,
  onInspect,
  onAnswer,
  onComplete,
  onResults,
}: {
  inspected: string[]
  activeMetric: string | null
  currentMetric: (typeof metrics)[number] | undefined
  answer: SimulationAnswer
  done: boolean
  onInspect: (id: string) => void
  onAnswer: (answer: SimulationAnswer) => void
  onComplete: () => void
  onResults: () => void
}) {
  const reducedMotion = useReducedMotion()
  const [analysing, setAnalysing] = useState(false)

  const submit = () => {
    if (!answer || inspected.length < 2 || analysing) return
    if (reducedMotion) {
      onComplete()
      return
    }
    setAnalysing(true)
    window.setTimeout(() => {
      setAnalysing(false)
      onComplete()
    }, 720)
  }

  return (
    <section className="simulation-screen screen-width wide">
      <div className="simulation-heading">
        <motion.div
          initial={reducedMotion ? false : { opacity: 0, x: -14 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.42 }}
        >
          <span className="section-eyebrow">Micro-simulation · Business analysis</span>
          <h2>Revenue is down 15%. What do you investigate first?</h2>
          <p>You joined a direct-to-consumer company this morning. The commercial lead wants an evidence-based first recommendation before the 15:00 meeting.</p>
        </motion.div>
        <motion.div
          className="simulation-badge"
          initial={reducedMotion ? false : { opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.18 }}
        >
          <Timer size={16} /> 2 min simulation
        </motion.div>
      </div>

      <div className="simulation-grid">
        <motion.div
          className="dashboard-panel"
          initial={reducedMotion ? false : { opacity: 0, y: 18 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.44, delay: reducedMotion ? 0 : 0.08 }}
        >
          <div className="panel-toolbar">
            <div>
              <span className="panel-kicker">Q3 performance</span>
              <strong>Commercial dashboard</strong>
            </div>
            <span className="live-pill"><span /> Updated 10 min ago</span>
          </div>

          <div className="metric-grid">
            {metrics.map((metric, index) => (
              <motion.button
                key={metric.id}
                className={'metric-card ' + (activeMetric === metric.id ? 'selected' : '')}
                onClick={() => onInspect(metric.id)}
                initial={reducedMotion ? false : { opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: reducedMotion ? 0 : 0.13 + index * 0.06 }}
                whileHover={reducedMotion ? undefined : { y: -4, scale: 1.012 }}
                whileTap={reducedMotion ? undefined : { scale: 0.97 }}
              >
                <div className="metric-top">
                  <span>{metric.label}</span>
                  <AnimatePresence>{inspected.includes(metric.id) && <MotionCheck />}</AnimatePresence>
                </div>
                <strong>{metric.value}</strong>
                <small className={metric.tone}>{metric.delta} vs Q2</small>
                {activeMetric === metric.id && (
                  <motion.span
                    layoutId="metric-focus"
                    className="metric-focus-ring"
                    transition={gentleSpring}
                  />
                )}
              </motion.button>
            ))}
          </div>

          <div className="chart-card">
            <div className="chart-title">
              <div><span>Revenue trend</span><strong>Last 6 months</strong></div>
              <span className="chart-total">€4.8m YTD</span>
            </div>
            <div className="bars">
              {[72, 78, 83, 86, 75, 58].map((height, index) => (
                <div className="bar-column" key={index}>
                  <motion.div
                    className={'bar ' + (index === 5 ? 'last' : '')}
                    initial={reducedMotion ? false : { height: 0, opacity: 0.5 }}
                    animate={{ height: height + '%', opacity: 1 }}
                    transition={{
                      delay: reducedMotion ? 0 : 0.24 + index * 0.07,
                      duration: reducedMotion ? 0 : 0.55,
                      ease: [0.2, 0.8, 0.2, 1],
                    }}
                  />
                  <span>{['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep'][index]}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="investigation-note">
            <Search size={17} />
            <span>Click the KPI cards to investigate. RoleQuest observes what you prioritise, not just your final answer.</span>
          </div>
        </motion.div>

        <motion.aside
          className="case-panel"
          initial={reducedMotion ? false : { opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.44, delay: reducedMotion ? 0 : 0.14 }}
        >
          <div className="case-step">
            <span>01</span>
            <div>
              <small>Investigate</small>
              <strong><AnimatedNumber value={inspected.length} duration={0.28} /> / 4 metrics opened</strong>
            </div>
          </div>

          <div className="metric-detail">
            <AnimatePresence mode="wait">
              <motion.div
                key={currentMetric?.id ?? 'empty'}
                initial={reducedMotion ? false : { opacity: 0, x: 12, filter: 'blur(4px)' }}
                animate={{ opacity: 1, x: 0, filter: 'blur(0px)' }}
                exit={reducedMotion ? undefined : { opacity: 0, x: -10, filter: 'blur(3px)' }}
                transition={{ duration: reducedMotion ? 0 : 0.24 }}
              >
                {currentMetric ? (
                  <>
                    <div className="detail-icon"><LineChart size={20} /></div>
                    <span className="panel-kicker">What you found</span>
                    <h3>{currentMetric.label}</h3>
                    <p>{currentMetric.detail}</p>
                  </>
                ) : (
                  <>
                    <div className="detail-icon muted"><Search size={20} /></div>
                    <span className="panel-kicker">Start investigating</span>
                    <h3>Open a KPI</h3>
                    <p>Choose the information you think is most useful. The order you inspect it is part of the simulation.</p>
                  </>
                )}
              </motion.div>
            </AnimatePresence>
          </div>

          <div className="case-divider" />

          <div className="case-step">
            <span>02</span>
            <div>
              <small>Prioritise</small>
              <strong>What deserves attention first?</strong>
            </div>
          </div>

          <div className="answer-list">
            {[
              ['conversion', 'Investigate the conversion drop', 'It is large enough to explain most of the revenue decline.'],
              ['traffic', 'Investigate traffic acquisition', 'Traffic changed, so channel quality may be the issue.'],
              ['order-value', 'Investigate order value', 'Customers might simply be spending less.'],
            ].map(([id, title, copy]) => (
              <motion.button
                className={'answer-option ' + (answer === id ? 'selected' : '')}
                key={id}
                onClick={() => onAnswer(id as SimulationAnswer)}
                whileHover={reducedMotion ? undefined : { x: 3 }}
                whileTap={reducedMotion ? undefined : { scale: 0.985 }}
              >
                <span className="radio">
                  <motion.span
                    animate={{ scale: answer === id ? 1 : 0, opacity: answer === id ? 1 : 0 }}
                    transition={softSpring}
                  />
                </span>
                <span><strong>{title}</strong><small>{copy}</small></span>
              </motion.button>
            ))}
          </div>

          <AnimatePresence mode="wait">
            {!done ? (
              <motion.button
                key="submit"
                className={'primary-button full arrow-button ' + (analysing ? 'analysing' : '')}
                disabled={!answer || inspected.length < 2 || analysing}
                onClick={submit}
                whileHover={!answer || reducedMotion ? undefined : { y: -2 }}
                whileTap={!answer || reducedMotion ? undefined : { scale: 0.97 }}
              >
                {analysing ? (
                  <>
                    <span className="analysis-spinner" />
                    Reading your approach…
                  </>
                ) : (
                  <>Submit recommendation <ArrowRight size={17} /></>
                )}
              </motion.button>
            ) : (
              <motion.div
                key="result"
                className="simulation-result"
                initial={reducedMotion ? false : { opacity: 0, height: 0, scale: 0.96 }}
                animate={{ opacity: 1, height: 'auto', scale: 1 }}
                exit={reducedMotion ? undefined : { opacity: 0 }}
                transition={gentleSpring}
              >
                <motion.div
                  className="result-check"
                  initial={reducedMotion ? false : { scale: 0.5, rotate: -18 }}
                  animate={{ scale: 1, rotate: 0 }}
                  transition={softSpring}
                >
                  <Check size={20} />
                </motion.div>
                <div>
                  <span className="panel-kicker">Simulation complete</span>
                  <h3>{answer === 'conversion' ? 'Strong prioritisation' : 'Evidence gathered'}</h3>
                  <p>
                    {answer === 'conversion'
                      ? 'You prioritised the largest commercial anomaly and used evidence before recommending the next step.'
                      : 'You explored the evidence before committing to a direction. RoleQuest recorded your investigation pattern.'}
                  </p>
                </div>
                <motion.button
                  className="primary-button full arrow-button"
                  onClick={onResults}
                  whileHover={reducedMotion ? undefined : { y: -2 }}
                  whileTap={reducedMotion ? undefined : { scale: 0.97 }}
                >
                  Build my Role DNA <Sparkles size={17} />
                </motion.button>
              </motion.div>
            )}
          </AnimatePresence>
        </motion.aside>
      </div>
    </section>
  )
}

type MatchItem = (typeof roleProfiles)[number] & { score: number }

function Results({
  traitScores,
  matches,
  onReset,
  likedCount,
}: {
  traitScores: Record<Trait, number>
  matches: MatchItem[]
  onReset: () => void
  likedCount: number
}) {
  const reducedMotion = useReducedMotion()
  const sortedTraits = (Object.keys(traitScores) as Trait[]).sort((a, b) => traitScores[b] - traitScores[a])
  const strongest = sortedTraits.slice(0, 3)

  return (
    <section className="results-screen screen-width wide">
      <div className="results-backglow" aria-hidden="true" />

      <motion.div
        className="results-hero"
        initial={reducedMotion ? false : { opacity: 0, y: 18 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.48 }}
      >
        <div>
          <motion.span
            className="section-eyebrow"
            initial={reducedMotion ? false : { opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.08 }}
          >
            Your Role DNA
          </motion.span>
          <h2>You're strongest where evidence meets decisions.</h2>
          <p>
            Based on your stated preferences, {likedCount} task reactions and your simulation behaviour.
            This is a career discovery signal, not a personality test.
          </p>
        </div>
        <motion.div
          className="dna-stamp"
          initial={reducedMotion ? false : { opacity: 0, scale: 0.9, rotate: 2 }}
          animate={{ opacity: 1, scale: 1, rotate: 0 }}
          transition={{ delay: reducedMotion ? 0 : 0.18, ...softSpring }}
        >
          <Target size={24} />
          <div><span>Profile confidence</span><strong>Strong signal</strong></div>
        </motion.div>
      </motion.div>

      <div className="results-grid">
        <motion.div
          className="dna-panel"
          initial={reducedMotion ? false : { opacity: 0, y: 18 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: reducedMotion ? 0 : 0.15, duration: 0.45 }}
        >
          <div className="panel-heading">
            <div>
              <span className="panel-kicker">Preference + behaviour</span>
              <h3>Your work profile</h3>
            </div>
            <motion.div
              animate={reducedMotion ? undefined : { rotate: [0, 8, -6, 0], scale: [1, 1.08, 1] }}
              transition={{ delay: 0.6, duration: 1 }}
            >
              <Sparkles size={20} />
            </motion.div>
          </div>

          <div className="trait-list">
            {sortedTraits.map((trait, index) => (
              <motion.div
                className="trait-row"
                key={trait}
                initial={reducedMotion ? false : { opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: reducedMotion ? 0 : 0.24 + index * 0.07 }}
              >
                <div className="trait-label">
                  <span>{traitLabels[trait]}</span>
                  <strong><AnimatedNumber value={traitScores[trait]} duration={0.7} /></strong>
                </div>
                <div className="trait-track">
                  <motion.div
                    className={'trait-fill ' + (index < 3 ? 'highlight' : '')}
                    initial={reducedMotion ? false : { width: 0 }}
                    animate={{ width: traitScores[trait] + '%' }}
                    transition={{
                      delay: reducedMotion ? 0 : 0.28 + index * 0.07,
                      duration: reducedMotion ? 0 : 0.7,
                      ease: [0.2, 0.8, 0.2, 1],
                    }}
                  />
                </div>
              </motion.div>
            ))}
          </div>

          <div className="strength-summary">
            <span className="panel-kicker">What stood out</span>
            {strongest.map((trait, index) => (
              <motion.div
                className="strength-item"
                key={trait}
                initial={reducedMotion ? false : { opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: reducedMotion ? 0 : 0.7 + index * 0.1 }}
              >
                <div><Check size={14} /></div>
                <p><strong>{traitLabels[trait]}</strong> {traitDescriptions[trait]}</p>
              </motion.div>
            ))}
          </div>
        </motion.div>

        <motion.div
          className="matches-panel"
          initial={reducedMotion ? false : { opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: reducedMotion ? 0 : 0.23, duration: 0.48 }}
        >
          <div className="panel-heading">
            <div>
              <span className="panel-kicker">Career matches</span>
              <h3>Roles worth exploring</h3>
            </div>
            <span className="explain-pill">Why this match?</span>
          </div>

          <div className="match-list">
            {matches.slice(0, 3).map((role, index) => (
              <motion.article
                className={'match-card ' + (index === 0 ? 'top-match' : '')}
                key={role.title}
                initial={reducedMotion ? false : { opacity: 0, y: 18, scale: 0.985 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                transition={{
                  delay: reducedMotion ? 0 : 0.4 + index * 0.14,
                  duration: 0.44,
                  ease: [0.2, 0.8, 0.2, 1],
                }}
                whileHover={reducedMotion ? undefined : { y: -3, scale: 1.006 }}
              >
                <div className="match-rank">0{index + 1}</div>
                <div className="match-main">
                  <div className="match-title-row">
                    <div>
                      <span className="role-type">{index === 0 ? 'Best current fit' : 'Also worth exploring'}</span>
                      <h4>{role.title}</h4>
                    </div>
                    <ScoreRing value={role.score} />
                  </div>
                  <p>{role.description}</p>
                  <motion.div
                    className="reason-box"
                    initial={reducedMotion ? false : { opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ delay: reducedMotion ? 0 : 0.68 + index * 0.14 }}
                  >
                    <Sparkles size={14} />
                    <span>
                      {role.title === 'Business Analyst'
                        ? 'You repeatedly chose analytical, structured work and prioritised the largest measurable anomaly in the simulation.'
                        : role.title === 'Product Analyst'
                          ? 'Your data orientation combines with autonomy and curiosity about how users and products behave.'
                          : 'You showed interest in ambiguous business problems, evidence-based decisions and situations involving other people.'}
                    </span>
                  </motion.div>
                  <div className="match-tags">
                    {role.traits.map((trait, traitIndex) => (
                      <motion.span
                        key={trait}
                        initial={reducedMotion ? false : { opacity: 0, scale: 0.85 }}
                        animate={{ opacity: 1, scale: 1 }}
                        transition={{ delay: reducedMotion ? 0 : 0.78 + index * 0.14 + traitIndex * 0.04 }}
                      >
                        {traitLabels[trait]}
                      </motion.span>
                    ))}
                  </div>
                </div>
              </motion.article>
            ))}
          </div>
        </motion.div>
      </div>

      <motion.div
        className="next-step-panel"
        initial={reducedMotion ? false : { opacity: 0, y: 18 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: reducedMotion ? 0 : 0.9, duration: 0.46 }}
      >
        <div className="next-step-icon"><BriefcaseBusiness size={22} /></div>
        <div>
          <span className="panel-kicker">The next RoleQuest step</span>
          <h3>Experience a real employer challenge.</h3>
          <p>In the full product, your strongest role matches would unlock employer-branded simulations and junior opportunities.</p>
        </div>
        <motion.button
          className="secondary-button restart-inline"
          onClick={onReset}
          whileHover={reducedMotion ? undefined : { y: -2 }}
          whileTap={reducedMotion ? undefined : { scale: 0.97 }}
        >
          Restart demo <RotateCcw size={16} />
        </motion.button>
      </motion.div>

      <motion.div
        className="results-footnote"
        initial={reducedMotion ? false : { opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: reducedMotion ? 0 : 1.02 }}
      >
        <CircleDollarSign size={15} />
        <span>Candidate access stays free. Employers pay for branded simulations, candidate skill insights and recruitment analytics.</span>
      </motion.div>
    </section>
  )
}

export default App
