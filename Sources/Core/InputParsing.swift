import Foundation

struct FlowInputResult {
    let date: Date
    let expression: String
    let fromNote: Bool
    let title: String
    let note: String
}
extension FlowClock {
    /// The title wins when both fields have a date. Remove only the expression used for the date.
    func parseInput(title: String, note: String, now: Date = Date()) -> FlowInputResult? {
        if let parsed = extractDate(from: title, now: now) {
            return FlowInputResult(date: parsed.date, expression: parsed.expression, fromNote: false, title: parsed.cleaned, note: note)
        }
        if let parsed = extractDate(from: note, now: now) {
            return FlowInputResult(date: parsed.date, expression: parsed.expression, fromNote: true, title: title, note: parsed.cleaned)
        }
        return nil
    }
    private func extractDate(from text: String, now: Date) -> (date: Date, expression: String, cleaned: String)? {
        // Matching on the original text preserves indexes even for full-width characters.
        let patterns = [
            #"(?<![\d０-９])[\d０-９]{4}[年/／\-－][\d０-９]{1,2}[月/／\-－][\d０-９]{1,2}日?(?![\d０-９])"#,
            #"(?<![\d０-９])[\d０-９]{1,2}月[\d０-９]{1,2}日"#,
            #"(?<![\d０-９/／])[\d０-９]{1,2}[/／][\d０-９]{1,2}(?![/／\d０-９])"#,
            #"明後日|明日|今日"#,
            #"(?:再来週|来週|今週)?[日月火水木金土]曜(?:日)?"#,
            #"再来年中|再来年末|来年中|来年末|今年中|今年末|今年いっぱい|年内|年末"#,
            #"再来月中|再来月末|来月中|来月末|今月中|今月末|今月いっぱい|月内|月末"#,
            #"再来週中|再来週末|来週中|来週末|今週中|今週末|週末"#,
            #"(?<![\d０-９.．-])[\d０-９]{1,3}(?:日|週間|か月|ヶ月|カ月|年)後"#,
            #"(?<![\d０-９A-Za-zＡ-Ｚａ-ｚ/／\-－])[\d０-９]{4}(?![\d０-９A-Za-zＡ-Ｚａ-ｚ年/／\-－])"#
        ]
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range, in: text) else { continue }
            let expression = String(text[range])
            // An explicit invalid date is left untouched instead of falling back to another token.
            guard let date = recognize(expression, now: now) else { return nil }
            var tail = String(text[range.upperBound...])
            for particle in ["までに", "まで", "に", "の"] where tail.hasPrefix(particle) {
                tail.removeFirst(particle.count)
                break
            }
            let cleaned = (String(text[..<range.lowerBound]) + tail).trimmingCharacters(in: .whitespacesAndNewlines)
            return (date, expression, cleaned)
        }
        return nil
    }
}

