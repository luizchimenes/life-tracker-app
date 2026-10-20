#if canImport(UIKit)
import SwiftUI
import UIKit

/// Lays out `FinancialReportPDFContent` as an A4, multipage, text-based PDF.
///
/// Drawn with UIKit text (so it is searchable and printable), independent of
/// the SwiftUI screens. Layout runs twice: the first pass counts pages so
/// every footer can show "Page X of Y".
struct FinancialReportPDFDocument {
    static let pageSize = CGSize(width: 595.28, height: 841.89)

    let content: FinancialReportPDFContent

    func render() -> Data {
        let bounds = CGRect(origin: .zero, size: Self.pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(content.documentTitle) — \(content.periodText)",
            kCGPDFContextCreator as String: "LifeTracker"
        ]

        var pageCount = 0
        _ = UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            let writer = PDFWriter(context: context, content: content, totalPages: nil)
            writer.drawDocument()
            pageCount = writer.page
        }

        return UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            PDFWriter(context: context, content: content, totalPages: pageCount).drawDocument()
        }
    }
}

// MARK: - Writer

private final class PDFWriter {
    private enum Style {
        static let margin: CGFloat = 40
        static let headerHeight: CGFloat = 56
        static let footerHeight: CGFloat = 40
        static let accent = UIColor(red: 0.18, green: 0.33, blue: 0.72, alpha: 1)
        static let text = UIColor(white: 0.12, alpha: 1)
        static let secondary = UIColor(white: 0.42, alpha: 1)
        static let rule = UIColor(white: 0.82, alpha: 1)
        static let zebra = UIColor(red: 0.95, green: 0.96, blue: 0.99, alpha: 1)
        static let tableHeader = UIColor(red: 0.88, green: 0.91, blue: 0.98, alpha: 1)
        static let cellPadding: CGFloat = 4
    }

    private let context: UIGraphicsPDFRendererContext
    private let content: FinancialReportPDFContent
    private let totalPages: Int?
    private let formatter: FinancialReportPDFContent.Formatter
    private let pageSize = FinancialReportPDFDocument.pageSize

    private(set) var page = 0
    private var y: CGFloat = 0
    /// Redrawn at the top of each new page while a table is in progress.
    private var continuation: (() -> Void)?

    private var left: CGFloat { Style.margin }
    private var width: CGFloat { pageSize.width - Style.margin * 2 }
    private var top: CGFloat { Style.headerHeight + 8 }
    private var bottom: CGFloat { pageSize.height - Style.footerHeight }

    init(context: UIGraphicsPDFRendererContext, content: FinancialReportPDFContent, totalPages: Int?) {
        self.context = context
        self.content = content
        self.totalPages = totalPages
        formatter = FinancialReportPDFContent.Formatter(locale: content.locale, calendar: content.calendar)
    }

    func drawDocument() {
        newPage()
        drawTitleBlock()
        for section in content.sections {
            drawSection(section)
        }
    }

    // MARK: Pages

    private func newPage() {
        context.beginPage()
        page += 1
        drawPageChrome()
        y = top
        continuation?()
    }

    private func ensureSpace(_ height: CGFloat) {
        if y + height > bottom {
            newPage()
        }
    }

    private func drawPageChrome() {
        let headerFont = UIFont.systemFont(ofSize: 8, weight: .medium)
        draw("\(content.documentTitle)  •  \(content.periodText)", font: headerFont, color: Style.secondary, x: left, y: 26, width: width * 0.75)
        draw("LifeTracker", font: UIFont.systemFont(ofSize: 8, weight: .bold), color: Style.accent, x: left, y: 26, width: width, alignment: .right)
        line(from: CGPoint(x: left, y: Style.headerHeight - 14), to: CGPoint(x: left + width, y: Style.headerHeight - 14), color: Style.rule)

        let footerY = pageSize.height - Style.footerHeight + 12
        line(from: CGPoint(x: left, y: footerY - 6), to: CGPoint(x: left + width, y: footerY - 6), color: Style.rule)
        draw(content.generatedText, font: headerFont, color: Style.secondary, x: left, y: footerY, width: width * 0.7)
        let pageText = totalPages.map { formatter.text("Page \(page) of \($0)") } ?? formatter.text("Page \(page)")
        draw(pageText, font: headerFont, color: Style.secondary, x: left, y: footerY, width: width, alignment: .right)
    }

    private func drawTitleBlock() {
        let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        y += draw(content.documentTitle, font: title, color: Style.text, x: left, y: y, width: width)
        y += 2
        y += draw(content.periodText, font: UIFont.systemFont(ofSize: 13, weight: .medium), color: Style.accent, x: left, y: y, width: width)
        y += 2
        y += draw(content.generatedText, font: UIFont.systemFont(ofSize: 9), color: Style.secondary, x: left, y: y, width: width)
        y += 14
    }

    // MARK: Sections

    private func drawSection(_ section: FinancialReportPDFContent.Section) {
        let headingFont = UIFont.systemFont(ofSize: 14, weight: .bold)
        // Keep a heading with at least a little of its content.
        ensureSpace(measure(section.title, font: headingFont, width: width) + 60)
        y += 6
        y += draw(section.title, font: headingFont, color: Style.accent, x: left, y: y, width: width)
        y += 3
        line(from: CGPoint(x: left, y: y), to: CGPoint(x: left + width, y: y), color: Style.accent, width: 1)
        y += 8

        drawRows(section.rows)
        if !section.chart.isEmpty {
            drawChart(section.chart)
        }
        for item in section.tables {
            if let title = item.title {
                drawSubheading(title)
            }
            drawTable(item.table)
        }
        for card in section.cards {
            drawSubheading(card.title)
            drawRows(card.rows)
            if !card.invoices.rows.isEmpty {
                drawTable(card.invoices)
            }
            if let installments = card.installments {
                drawTable(installments)
            }
        }
        for bullet in section.bullets {
            drawParagraph("•  " + bullet, font: UIFont.systemFont(ofSize: 9.5), color: Style.text)
        }
        for note in section.notes {
            drawParagraph(note, font: UIFont.italicSystemFont(ofSize: 8.5), color: Style.secondary)
        }
        y += 10
    }

    private func drawSubheading(_ text: String) {
        let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        ensureSpace(measure(text, font: font, width: width) + 40)
        y += 4
        y += draw(text, font: font, color: Style.text, x: left, y: y, width: width)
        y += 4
    }

    private func drawParagraph(_ text: String, font: UIFont, color: UIColor) {
        let height = measure(text, font: font, width: width)
        ensureSpace(height + 4)
        y += draw(text, font: font, color: color, x: left, y: y, width: width) + 4
    }

    private func drawRows(_ rows: [FinancialReportPDFContent.Row]) {
        let labelWidth = width * 0.58
        let valueWidth = width - labelWidth
        for row in rows {
            let labelFont = UIFont.systemFont(ofSize: 10, weight: row.emphasized ? .semibold : .regular)
            let valueFont = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: row.emphasized ? .bold : .medium)
            let detailFont = UIFont.systemFont(ofSize: 8)
            let detailHeight = row.detail.map { measure($0, font: detailFont, width: valueWidth) } ?? 0
            let height = max(measure(row.label, font: labelFont, width: labelWidth), measure(row.value, font: valueFont, width: valueWidth) + detailHeight)
            ensureSpace(height + 6)
            draw(row.label, font: labelFont, color: Style.text, x: left, y: y, width: labelWidth)
            let valueHeight = draw(row.value, font: valueFont, color: Style.text, x: left + labelWidth, y: y, width: valueWidth, alignment: .right)
            if let detail = row.detail {
                draw(detail, font: detailFont, color: Style.secondary, x: left + labelWidth, y: y + valueHeight, width: valueWidth, alignment: .right)
            }
            y += height + 3
            line(from: CGPoint(x: left, y: y), to: CGPoint(x: left + width, y: y), color: Style.rule, width: 0.4)
            y += 3
        }
        if !rows.isEmpty {
            y += 4
        }
    }

    // MARK: Chart

    private func drawChart(_ bars: [FinancialReportPDFContent.ChartBar]) {
        let font = UIFont.systemFont(ofSize: 8.5)
        let rowHeight: CGFloat = 16
        let labelWidth = width * 0.26
        let valueWidth = width * 0.20
        let barArea = width - labelWidth - valueWidth - 12
        let maxValue = bars.map(\.value).max() ?? 0

        for bar in bars {
            ensureSpace(rowHeight)
            draw(bar.label, font: font, color: Style.text, x: left, y: y + 2, width: labelWidth - 6, lines: 1)
            let length = maxValue > 0 ? CGFloat(bar.value / maxValue) * barArea : 0
            let rect = CGRect(x: left + labelWidth, y: y + 3, width: max(length, 1.5), height: rowHeight - 6)
            UIColor(Color.category(named: bar.colorName)).withAlphaComponent(0.85).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()
            draw(bar.valueText, font: UIFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium), color: Style.text, x: left + width - valueWidth, y: y + 2, width: valueWidth, alignment: .right)
            y += rowHeight
        }
        y += 8
    }

    // MARK: Tables

    private func drawTable(_ table: FinancialReportPDFContent.Table) {
        let bodyFont = UIFont.systemFont(ofSize: 8.5)
        let headerFont = UIFont.systemFont(ofSize: 8, weight: .semibold)
        let widths = table.columns.map { CGFloat($0.width) * width }

        let drawHeader = { [self] in
            let height = rowHeight(table.columns.map(\.title), widths: widths, font: headerFont)
            Style.tableHeader.setFill()
            UIRectFill(CGRect(x: left, y: y, width: width, height: height))
            drawCells(table.columns.map(\.title), columns: table.columns, widths: widths, font: headerFont, color: Style.text)
            y += height
        }

        ensureSpace(rowHeight(table.columns.map(\.title), widths: widths, font: headerFont) + 18)
        drawHeader()
        continuation = drawHeader

        for (index, row) in table.rows.enumerated() {
            let height = rowHeight(row, widths: widths, font: bodyFont)
            ensureSpace(height)
            if index.isMultiple(of: 2) == false {
                Style.zebra.setFill()
                UIRectFill(CGRect(x: left, y: y, width: width, height: height))
            }
            drawCells(row, columns: table.columns, widths: widths, font: bodyFont, color: Style.text)
            y += height
        }

        continuation = nil

        if let footer = table.footer {
            let footerFont = UIFont.systemFont(ofSize: 8.5, weight: .bold)
            let height = rowHeight(footer, widths: widths, font: footerFont)
            ensureSpace(height)
            line(from: CGPoint(x: left, y: y), to: CGPoint(x: left + width, y: y), color: Style.text, width: 0.6)
            drawCells(footer, columns: table.columns, widths: widths, font: footerFont, color: Style.text)
            y += height
        }
        y += 10
    }

    private func rowHeight(_ cells: [String], widths: [CGFloat], font: UIFont) -> CGFloat {
        zip(cells, widths)
            .map { measure($0.0, font: font, width: $0.1 - Style.cellPadding * 2) }
            .max()
            .map { $0 + Style.cellPadding * 2 } ?? 0
    }

    private func drawCells(
        _ cells: [String],
        columns: [FinancialReportPDFContent.Column],
        widths: [CGFloat],
        font: UIFont,
        color: UIColor
    ) {
        var x = left
        for (index, cell) in cells.enumerated() where index < columns.count {
            let alignment: NSTextAlignment = columns[index].alignment == .trailing ? .right : .left
            let cellFont = alignment == .right ? UIFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: font.weight) : font
            draw(cell, font: cellFont, color: color, x: x + Style.cellPadding, y: y + Style.cellPadding, width: widths[index] - Style.cellPadding * 2, alignment: alignment)
            x += widths[index]
        }
    }

    // MARK: Primitives

    private func attributes(font: UIFont, color: UIColor, alignment: NSTextAlignment, lines: Int) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private func measure(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return font.lineHeight }
        let rect = NSAttributedString(string: text, attributes: attributes(font: font, color: Style.text, alignment: .left, lines: 0))
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(rect.height)
    }

    @discardableResult
    private func draw(
        _ text: String,
        font: UIFont,
        color: UIColor,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        alignment: NSTextAlignment = .left,
        lines: Int = 0
    ) -> CGFloat {
        let height = lines == 1 ? ceil(font.lineHeight) : measure(text, font: font, width: width)
        NSAttributedString(string: text, attributes: attributes(font: font, color: color, alignment: alignment, lines: lines))
            .draw(with: CGRect(x: x, y: y, width: width, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return height
    }

    private func line(from start: CGPoint, to end: CGPoint, color: UIColor, width: CGFloat = 0.5) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }
}

private extension UIFont {
    var weight: UIFont.Weight {
        let traits = fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        return (traits?[.weight] as? CGFloat).map { UIFont.Weight($0) } ?? .regular
    }
}
#endif
