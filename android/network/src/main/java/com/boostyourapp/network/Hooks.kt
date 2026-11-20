package com.boostyourapp.network

/**
 * Mots surlignés des accroches : un passage entre étoiles (« Prêt en *5 minutes* ») est surligné en style
 * dynamique ; les autres styles affichent l'accroche sans les étoiles. Même règle que le back-office
 * (shared/utils/boost.ts, hookSegments).
 */
internal object Hooks {
    private val MARKED = Regex("""\*([^*]+)\*""")

    /** Texte sans étoiles et positions des passages surlignés dans ce texte */
    data class Marked(val text: String, val marks: List<IntRange>)

    fun parse(hook: String): Marked {
        val text = StringBuilder()
        val marks = ArrayList<IntRange>()
        var last = 0
        for (match in MARKED.findAll(hook)) {
            text.append(hook, last, match.range.first)
            val word = match.groupValues[1]
            marks += text.length until text.length + word.length
            text.append(word)
            last = match.range.last + 1
        }
        text.append(hook, last, hook.length)
        return Marked(text.toString(), marks)
    }

    fun plain(hook: String): String = MARKED.replace(hook, "$1")
}
