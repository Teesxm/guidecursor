export type Trait =
  | 'analytical'
  | 'creative'
  | 'social'
  | 'structured'
  | 'autonomy'
  | 'decision'

export type Task = {
  id: number
  category: string
  context: string
  prompt: string
  detail: string
  image: string
  traits: Trait[]
  reveal: string
}

export const onboardingQuestions = [
  {
    id: 'problem-style',
    eyebrow: 'How you like to solve problems',
    question: 'Which kind of challenge pulls you in more?',
    left: { label: 'Make sense of data', trait: 'analytical' as Trait, icon: 'ChartNoAxesCombined' },
    right: { label: 'Generate new ideas', trait: 'creative' as Trait, icon: 'Sparkles' },
  },
  {
    id: 'work-energy',
    eyebrow: 'Where you get energy',
    question: 'What sounds more naturally motivating?',
    left: { label: 'Deep independent focus', trait: 'autonomy' as Trait, icon: 'Focus' },
    right: { label: 'Working with people', trait: 'social' as Trait, icon: 'Users' },
  },
  {
    id: 'work-style',
    eyebrow: 'Your preferred work style',
    question: 'Which environment would you rather enter?',
    left: { label: 'Clear goals and structure', trait: 'structured' as Trait, icon: 'ListChecks' },
    right: { label: 'Freedom to shape the approach', trait: 'autonomy' as Trait, icon: 'Route' },
  },
  {
    id: 'impact',
    eyebrow: 'How you like to create impact',
    question: 'Which responsibility sounds more satisfying?',
    left: { label: 'Advise with evidence', trait: 'analytical' as Trait, icon: 'SearchCheck' },
    right: { label: 'Influence a decision', trait: 'decision' as Trait, icon: 'Gavel' },
  },
  {
    id: 'pace',
    eyebrow: 'The pace you enjoy',
    question: 'Pick the situation you would rather own.',
    left: { label: 'Improve a system carefully', trait: 'structured' as Trait, icon: 'Settings2' },
    right: { label: 'React and decide quickly', trait: 'decision' as Trait, icon: 'Zap' },
  },
] as const

export const tasks: Task[] = [
  {
    id: 1,
    category: 'Growth problem',
    context: 'Monday, 09:20 · Consumer app',
    prompt: 'A product launch is underperforming.',
    detail: 'You have sales data, customer reviews and website analytics. Your manager asks you to figure out what went wrong and what to investigate first.',
    image: 'https://images.unsplash.com/photo-1556761175-b413da4baf72?auto=format&fit=crop&w=1400&q=85',
    traits: ['analytical', 'decision'],
    reveal: 'Common in Business Analysis, Product Analytics and Consulting.',
  },
  {
    id: 2,
    category: 'Creative brief',
    context: 'Tuesday, 13:40 · Lifestyle brand',
    prompt: 'A campaign is getting attention but nobody remembers the brand.',
    detail: 'You need to turn audience research into a sharper campaign idea and pitch a new creative direction before Friday.',
    image: 'https://images.unsplash.com/photo-1521737711867-e3b97375f902?auto=format&fit=crop&w=1400&q=85',
    traits: ['creative', 'social'],
    reveal: 'Common in Brand Marketing, Creative Strategy and Advertising.',
  },
  {
    id: 3,
    category: 'Client challenge',
    context: 'Wednesday, 10:10 · B2B project',
    prompt: 'A client rejects the recommendation your team prepared.',
    detail: 'You have 30 minutes to understand their concern, adapt the argument and decide what evidence could change their mind.',
    image: 'https://images.unsplash.com/photo-1551836022-d5d88e9218df?auto=format&fit=crop&w=1400&q=85',
    traits: ['social', 'decision', 'analytical'],
    reveal: 'Common in Consulting, Sales and Account Management.',
  },
  {
    id: 4,
    category: 'Process puzzle',
    context: 'Thursday, 15:15 · Operations team',
    prompt: 'Orders are arriving late even though every team says they are on schedule.',
    detail: 'You map the handoffs, compare timestamps and identify where the process is actually slowing down.',
    image: 'https://images.unsplash.com/photo-1552664730-d307ca884978?auto=format&fit=crop&w=1400&q=85',
    traits: ['structured', 'analytical'],
    reveal: 'Common in Operations, Supply Chain and Process Improvement.',
  },
  {
    id: 5,
    category: 'People decision',
    context: 'Friday, 11:30 · Graduate programme',
    prompt: 'Two strong candidates perform very differently in the final round.',
    detail: 'You compare interview evidence, team needs and assessment results before recommending who should move forward.',
    image: 'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?auto=format&fit=crop&w=1400&q=85',
    traits: ['social', 'structured', 'decision'],
    reveal: 'Common in Talent, People Operations and Recruitment.',
  },
  {
    id: 6,
    category: 'Commercial opportunity',
    context: 'Monday, 16:00 · Software company',
    prompt: 'A customer likes the product but says switching is too risky.',
    detail: 'You need to uncover the real objection, build a business case and decide how to move the conversation forward.',
    image: 'https://images.unsplash.com/photo-1524178232363-1fb2b075b655?auto=format&fit=crop&w=1400&q=85',
    traits: ['social', 'decision', 'autonomy'],
    reveal: 'Common in B2B Sales, Partnerships and Customer Success.',
  },
  {
    id: 7,
    category: 'Product trade-off',
    context: 'Tuesday, 09:45 · Product squad',
    prompt: 'Users want three different features, but the team can only build one.',
    detail: 'You combine customer evidence, business impact and engineering effort to recommend what should be prioritised.',
    image: 'https://images.unsplash.com/photo-1559136555-9303baea8ebd?auto=format&fit=crop&w=1400&q=85',
    traits: ['decision', 'analytical', 'creative'],
    reveal: 'Common in Product Management, Product Strategy and Innovation.',
  },
  {
    id: 8,
    category: 'Market question',
    context: 'Wednesday, 14:20 · International expansion',
    prompt: 'Your company is considering entering a new European market.',
    detail: 'You have one afternoon to compare demand, competitors, regulation and economics before recommending whether to investigate further.',
    image: 'https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?auto=format&fit=crop&w=1400&q=85',
    traits: ['analytical', 'autonomy', 'structured'],
    reveal: 'Common in Strategy, Market Intelligence and Business Development.',
  },
]

export const roleProfiles = [
  {
    title: 'Business Analyst',
    base: 82,
    traits: ['analytical', 'structured', 'decision'] as Trait[],
    description: 'Turn business questions into evidence, spot patterns and help teams make better decisions.',
  },
  {
    title: 'Product Analyst',
    base: 77,
    traits: ['analytical', 'autonomy', 'creative'] as Trait[],
    description: 'Use product and user data to explain behaviour and guide what a digital team should improve next.',
  },
  {
    title: 'Strategy Consultant',
    base: 72,
    traits: ['analytical', 'social', 'decision'] as Trait[],
    description: 'Structure ambiguous problems, communicate recommendations and work across different business challenges.',
  },
  {
    title: 'Product Manager',
    base: 69,
    traits: ['decision', 'creative', 'social'] as Trait[],
    description: 'Balance user needs, business goals and constraints to decide what a product team should build.',
  },
]
