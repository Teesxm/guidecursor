import { useEffect, useState } from 'react'
import { motion, useReducedMotion } from 'motion/react'

export const softSpring = {
  type: 'spring' as const,
  stiffness: 260,
  damping: 28,
  mass: 0.8,
}

export const gentleSpring = {
  type: 'spring' as const,
  stiffness: 180,
  damping: 24,
  mass: 0.9,
}

export function AnimatedNumber({
  value,
  suffix = '',
  duration = 0.8,
}: {
  value: number
  suffix?: string
  duration?: number
}) {
  const reducedMotion = useReducedMotion()
  const [display, setDisplay] = useState(reducedMotion ? value : 0)

  useEffect(() => {
    if (reducedMotion) {
      setDisplay(value)
      return
    }

    const start = performance.now()
    const from = display
    let frame = 0

    const tick = (now: number) => {
      const progress = Math.min(1, (now - start) / (duration * 1000))
      const eased = 1 - Math.pow(1 - progress, 3)
      setDisplay(Math.round(from + (value - from) * eased))
      if (progress < 1) frame = requestAnimationFrame(tick)
    }

    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
    // Intentionally animate from the currently displayed value.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, duration, reducedMotion])

  return <>{display}{suffix}</>
}

export function ScoreRing({ value }: { value: number }) {
  const reducedMotion = useReducedMotion()
  const radius = 20
  const circumference = 2 * Math.PI * radius
  const dash = circumference * (value / 100)

  return (
    <div className="score-ring">
      <svg viewBox="0 0 48 48" aria-hidden="true">
        <circle className="score-ring-track" cx="24" cy="24" r={radius} />
        <motion.circle
          className="score-ring-progress"
          cx="24"
          cy="24"
          r={radius}
          initial={{ strokeDasharray: `0 ${circumference}` }}
          animate={{ strokeDasharray: `${dash} ${circumference - dash}` }}
          transition={reducedMotion ? { duration: 0 } : { duration: 0.9, delay: 0.2, ease: [0.2, 0.8, 0.2, 1] }}
        />
      </svg>
      <strong><AnimatedNumber value={value} suffix="%" /></strong>
    </div>
  )
}

export function MotionCheck() {
  const reducedMotion = useReducedMotion()

  return (
    <motion.span
      className="motion-check"
      initial={reducedMotion ? false : { scale: 0.5, opacity: 0, rotate: -25 }}
      animate={{ scale: 1, opacity: 1, rotate: 0 }}
      exit={reducedMotion ? undefined : { scale: 0.6, opacity: 0 }}
      transition={softSpring}
    >
      ✓
    </motion.span>
  )
}
