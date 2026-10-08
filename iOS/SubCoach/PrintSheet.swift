import SwiftUI
import UIKit

/// The same landscape sheet the web version printed, drawn as a one-page PDF.
enum PrintSheet {
    static let page = CGSize(width: 792, height: 612) // US Letter, landscape
    static let margin: CGFloat = 34

    @MainActor static func pdf(_ s: LineupState) -> Data {
        let content = CGSize(width: page.width - margin * 2, height: page.height - margin * 2)
        let renderer = ImageRenderer(content: SheetView(s: s).frame(width: content.width))
        let data = NSMutableData()
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: page)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            // Shrink to fit if the roster is too long for one page.
            let scale = min(1, content.height / size.height, content.width / size.width)
            ctx.translateBy(x: margin, y: page.height - margin - size.height * scale)
            ctx.scaleBy(x: scale, y: scale)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return data as Data
    }

    @MainActor static func present(_ s: LineupState) {
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.orientation = .landscape
        info.jobName = s.title.isEmpty ? "Lineup" : s.title
        let pic = UIPrintInteractionController.shared
        pic.printInfo = info
        pic.printingItem = pdf(s)
        pic.present(animated: true)
    }

    private struct SheetView: View {
        let s: LineupState

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.title.isEmpty ? "Lineup" : s.title).font(.system(size: 22, weight: .bold))
                Text("Two \(s.halfMinutes)-minute halves.\(subText)").font(.system(size: 12))
                    .padding(.bottom, 10)
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        cell("", header: true)
                        cell("First half", header: true).gridCellColumns(s.perHalf)
                        cell("Second half", header: true, halfLine: true).gridCellColumns(s.perHalf)
                        cell("", header: true)
                    }
                    GridRow {
                        cell("Player", header: true, leading: true)
                        ForEach(0..<s.periods, id: \.self) { p in
                            cell("\(p + 1) (\(s.startAt(p % s.perHalf)))", header: true, halfLine: p == s.perHalf)
                        }
                        cell("Periods", header: true)
                    }
                    ForEach(s.players) { pl in
                        GridRow {
                            cell(pl.name, leading: true, bold: true)
                            ForEach(0..<s.periods, id: \.self) { p in
                                let c = pl.cell(p)
                                cell(c.map { s.positionName($0) } ?? "bench", dim: c == nil, halfLine: p == s.perHalf)
                            }
                            cell("\(pl.periodsPlayed)")
                        }
                    }
                }
            }
            .foregroundStyle(.black)
            .background(.white)
            .environment(\.colorScheme, .light)
        }

        private var subText: String {
            let subs = (1..<max(s.perHalf, 1)).map { s.startAt($0) }
            guard let last = subs.last else { return "" }
            return " Substitute at " + (subs.count > 1 ? subs.dropLast().joined(separator: ", ") + " and " + last : last) + " of each half."
        }

        private func cell(_ text: String, header: Bool = false, leading: Bool = false, bold: Bool = false, dim: Bool = false, halfLine: Bool = false) -> some View {
            Text(text)
                .font(.system(size: header ? 12 : 15, weight: header || bold ? .bold : .regular))
                .foregroundStyle(dim ? Color(white: 0.47) : .black)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: header ? 24 : 30, alignment: leading ? .leading : .center)
                .background(header ? Color(white: 0.9) : .white)
                .overlay { Rectangle().strokeBorder(.black, lineWidth: 0.5) }
                .overlay(alignment: .leading) { if halfLine { Rectangle().fill(.black).frame(width: 2.5) } }
        }
    }
}
