// Editorial starting references for common questions, never an exhaustive doctrinal index.
// Ranking still searches the full corpus. Two anchors leave room for independently ranked passages.
const GUIDES: { words: string[]; references: string[] }[] = [
  { words: ['anxiety', 'anxious', 'worry', 'worried', 'worries'], references: ['Matthew 6:25-34', 'Philippians 4:4-9'] },
  { words: ['forgive', 'forgiveness', 'forgiving'], references: ['Matthew 6:9-15', 'Colossians 3:12-17'] },
  { words: ['pray', 'prayer', 'praying'], references: ['Matthew 6:5-13', 'Luke 11:1-13'] },
  { words: ['jewish', 'jews', 'judaism', 'antisemitism'], references: ['Romans 11:13-24', 'Ephesians 2:11-22'] },
  { words: ['suffering', 'suffer', 'affliction'], references: ['Romans 5:1-5', 'Job 2:7-13'] },
  { words: ['grief', 'grieving', 'mourn', 'mourning'], references: ['John 11:32-36', 'Psalms 34:15-19'] },
  { words: ['salvation', 'saved'], references: ['Ephesians 2:1-10', 'Romans 10:8-13'] },
  { words: ['resurrection', 'risen'], references: ['1 Corinthians 15:12-22', 'Luke 24:1-12'] },
  { words: ['baptism', 'baptize', 'baptized'], references: ['Romans 6:1-7', 'Acts 2:37-41'] },
  { words: ['anger', 'angry'], references: ['James 1:19-21', 'Ephesians 4:25-32'] },
  { words: ['temptation', 'tempted'], references: ['James 1:12-18', '1 Corinthians 10:12-13'] },
  { words: ['wealth', 'money', 'greed'], references: ['1 Timothy 6:6-10', 'Matthew 6:19-24'] },
  { words: ['justice', 'injustice'], references: ['Micah 6:6-8', 'Isaiah 1:16-20'] },
];

export function topicReferences(query: string): string[] {
  const words = new Set(query.toLowerCase().match(/[a-z]+/g));
  const matched = GUIDES.filter(guide => guide.words.some(word => words.has(word)));
  // For a comparison of topics, offer one starting reference from each.
  return matched.length > 1 ? matched.slice(0, 2).map(guide => guide.references[0]!) : matched[0]?.references ?? [];
}
