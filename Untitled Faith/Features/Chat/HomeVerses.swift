import Foundation

/// Verses shown on the empty chat screen.
///
/// Text is quoted from the ESV® Bible under Crossway's standard quotation permission
/// (fewer than 1,000 verses, no complete book). The required copyright notice is shown
/// in Settings › Answer sources. Verify wording against esv.org before release.
enum HomeVerses {
    static let esv: [ScriptureCitation] = [
        verse("John 3:16", "For God so loved the world, that he gave his only Son, that whoever believes in him should not perish but have eternal life."),
        verse("Psalm 23:1", "The LORD is my shepherd; I shall not want."),
        verse("Philippians 4:13", "I can do all things through him who strengthens me."),
        verse("Proverbs 3:5–6", "Trust in the LORD with all your heart, and do not lean on your own understanding. In all your ways acknowledge him, and he will make straight your paths."),
        verse("Romans 8:28", "And we know that for those who love God all things work together for good, for those who are called according to his purpose."),
        verse("Matthew 11:28", "Come to me, all who labor and are heavy laden, and I will give you rest."),
        verse("Psalm 46:10", "Be still, and know that I am God. I will be exalted among the nations, I will be exalted in the earth!"),
        verse("Joshua 1:9", "Have I not commanded you? Be strong and courageous. Do not be frightened, and do not be dismayed, for the LORD your God is with you wherever you go."),
        verse("Psalm 119:105", "Your word is a lamp to my feet and a light to my path."),
        verse("Jeremiah 29:11", "For I know the plans I have for you, declares the LORD, plans for welfare and not for evil, to give you a future and a hope."),
        verse("Lamentations 3:22–23", "The steadfast love of the LORD never ceases; his mercies never come to an end; they are new every morning; great is your faithfulness."),
        verse("Hebrews 11:1", "Now faith is the assurance of things hoped for, the conviction of things not seen."),
        verse("Matthew 6:33", "But seek first the kingdom of God and his righteousness, and all these things will be added to you."),
        verse("2 Corinthians 5:17", "Therefore, if anyone is in Christ, he is a new creation. The old has passed away; behold, the new has come."),
        verse("Psalm 46:1", "God is our refuge and strength, a very present help in trouble."),
        verse("Romans 15:13", "May the God of hope fill you with all joy and peace in believing, so that by the power of the Holy Spirit you may abound in hope."),
        verse("1 John 4:19", "We love because he first loved us."),
        verse("Psalm 118:24", "This is the day that the LORD has made; let us rejoice and be glad in it."),
        verse("1 Thessalonians 5:16–18", "Rejoice always, pray without ceasing, give thanks in all circumstances; for this is the will of God in Christ Jesus for you."),
        verse("Psalm 56:3", "When I am afraid, I put my trust in you."),
        verse("Isaiah 26:3", "You keep him in perfect peace whose mind is stayed on you, because he trusts in you."),
        verse("John 16:33", "I have said these things to you, that in me you may have peace. In the world you will have tribulation. But take heart; I have overcome the world."),
        verse("Psalm 37:4", "Delight yourself in the LORD, and he will give you the desires of your heart."),
        verse("1 Corinthians 13:13", "So now faith, hope, and love abide, these three; but the greatest of these is love."),
        verse("Matthew 7:7", "Ask, and it will be given to you; seek, and you will find; knock, and it will be opened to you."),
        verse("Psalm 27:1", "The LORD is my light and my salvation; whom shall I fear? The LORD is the stronghold of my life; of whom shall I be afraid?"),
        verse("Micah 6:8", "He has told you, O man, what is good; and what does the LORD require of you but to do justice, and to love kindness, and to walk humbly with your God?"),
        verse("Ephesians 2:8–9", "For by grace you have been saved through faith. And this is not your own doing; it is the gift of God, not a result of works, so that no one may boast."),
        verse("James 1:5", "If any of you lacks wisdom, let him ask God, who gives generously to all without reproach, and it will be given him."),
        verse("Psalm 121:1–2", "I lift up my eyes to the hills. From where does my help come? My help comes from the LORD, who made heaven and earth."),
        verse("Deuteronomy 31:6", "Be strong and courageous. Do not fear or be in dread of them, for it is the LORD your God who goes with you. He will not leave you or forsake you."),
        verse("Proverbs 18:10", "The name of the LORD is a strong tower; the righteous man runs into it and is safe."),
        verse("Psalm 34:8", "Oh, taste and see that the LORD is good! Blessed is the man who takes refuge in him!"),
        verse("Nahum 1:7", "The LORD is good, a stronghold in the day of trouble; he knows those who take refuge in him."),
        verse("Psalm 100:5", "For the LORD is good; his steadfast love endures forever, and his faithfulness to all generations."),
        verse("Psalm 16:11", "You make known to me the path of life; in your presence there is fullness of joy; at your right hand are pleasures forevermore.")
    ]

    private static func verse(_ reference: String, _ passage: String) -> ScriptureCitation {
        ScriptureCitation(id: UUID(), reference: reference, translation: "ESV", passage: passage)
    }
}
