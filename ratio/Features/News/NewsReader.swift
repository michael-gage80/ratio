import FirebaseStorage
import OSLog
import SafariServices
import SwiftUI

// The Week in Law's reader: stories whose text Ratio may show (official sources under
// open licences, and publishers who've agreed) typeset like a law report, from
// news/{id}/{part}.json (functions/src/article.ts). Everything else opens in Safari's
// Reader view inside the app; subscriber-only stories open in Safari itself.

// MARK: - Document

/// A run of inline text: italic, bold, or a link.
nonisolated struct NewsRun: Decodable, Equatable {
    var t: String
    var i: Bool?
    var b: Bool?
    var href: String?
}

nonisolated enum NewsBlock: Decodable, Equatable {
    case heading([NewsRun])
    /// `number`: a judgment's paragraph number.
    case paragraph([NewsRun], number: String?)
    case quote([NewsRun])
    case list(ordered: Bool, items: [[NewsRun]])
    case table([[String]])
    /// A lead image in Storage.
    case image(path: String, alt: String?)

    private enum CodingKeys: String, CodingKey {
        case k, runs, n, ordered, items, rows, src, alt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .k) {
        case "h": self = .heading(try c.decode([NewsRun].self, forKey: .runs))
        case "q": self = .quote(try c.decode([NewsRun].self, forKey: .runs))
        case "list": self = .list(ordered: try c.decode(Bool.self, forKey: .ordered), items: try c.decode([[NewsRun]].self, forKey: .items))
        case "table": self = .table(try c.decode([[String]].self, forKey: .rows))
        case "img": self = .image(path: try c.decode(String.self, forKey: .src), alt: try c.decodeIfPresent(String.self, forKey: .alt))
        default: self = .paragraph(try c.decode([NewsRun].self, forKey: .runs), number: try c.decodeIfPresent(String.self, forKey: .n))
        }
    }
}

nonisolated struct NewsArticle: Decodable, Equatable {
    var title: String
    var source: String
    var url: String
    var licence: String
    var byline: String?
    var words: Int
    var blocks: [NewsBlock]
}

/// Articles fetched this session, so going back and forth doesn't download them again.
@MainActor
enum NewsArticles {
    private static var cache: [String: NewsArticle] = [:]

    static func load(storyId: String, part: String) async throws -> NewsArticle {
        let key = "\(storyId)/\(part)"
        if let cached = cache[key] { return cached }
        let data = try await Storage.storage().reference(withPath: "news/\(key).json").data(maxSize: 4 * 1024 * 1024)
        let article = try JSONDecoder().decode(NewsArticle.self, from: data)
        cache[key] = article
        return article
    }
}

// MARK: - Read marks and positions (on the phone)

enum NewsReading {
    static let readKey = "news.read"

    /// Stories opened, newest last (kept to the last 300).
    static func markRead(_ id: String, in stored: inout String) {
        var ids = stored.split(separator: ",").map(String.init).filter { $0 != id }
        ids.append(id)
        stored = ids.suffix(300).joined(separator: ",")
    }

    static func isRead(_ id: String, in stored: String) -> Bool {
        stored.split(separator: ",").contains { $0 == id }
    }

    /// The block the student had scrolled to, per story and part.
    static func position(storyId: String, part: String) -> Int? {
        let key = "news.position.\(storyId).\(part)"
        return UserDefaults.standard.object(forKey: key) == nil ? nil : UserDefaults.standard.integer(forKey: key)
    }

    static func setPosition(_ index: Int, storyId: String, part: String) {
        UserDefaults.standard.set(index, forKey: "news.position.\(storyId).\(part)")
    }
}

// MARK: - Opening a story

/// Where a story opens: Ratio's reader, Safari's Reader view in the app, or Safari
/// itself for subscriber-only stories (so a subscriber can sign in).
enum NewsOpening {
    case reader
    case inApp(URL)
    case safari(URL)

    init?(_ story: NewsStory) {
        if story.reader != nil, story.paywalled != true {
            self = .reader
        } else if let link = story.link {
            self = story.paywalled == true ? .safari(link) : .inApp(link)
        } else {
            return nil
        }
    }
}

/// A URL for `.fullScreenCover(item:)`.
struct SafariLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Safari inside the app, straight into Reader view where the page allows it.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: configuration)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

// MARK: - Reader

struct NewsReaderView: View {
    let storyId: String

    @Environment(StudentStore.self) private var student
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var systemSize
    @AppStorage(NewsReading.readKey) private var read = ""
    @AppStorage(RatioPreferences.dyslexia) private var dyslexia = false
    /// The student's reader text size (a DynamicTypeSize index); -1 follows the system.
    @AppStorage("news.textSize") private var textSize = -1
    #if DEBUG
    /// "-newsPart judgment" (debug screenshots) opens that part.
    @State private var part: String? = UserDefaults.standard.string(forKey: "newsPart")
    #else
    @State private var part: String?
    #endif
    @State private var article: NewsArticle?
    @State private var failed = false
    @State private var position: Int?
    /// Where to return to once the article is laid out.
    @State private var resumeAt: Int?
    @State private var safari: SafariLink?

    private var story: NewsStory? { student.news.first { $0.id == storyId } }
    private static let sizes = DynamicTypeSize.allCases
    private var sizeIndex: Int {
        textSize >= 0 ? min(textSize, Self.sizes.count - 1) : Self.sizes.firstIndex(of: systemSize) ?? 3
    }

    var body: some View {
        Group {
            if let story, let article {
                content(story, article)
            } else if failed, let story {
                RatioEmptyState(message: "This story couldn't be loaded.", actionTitle: story.link == nil ? nil : "Open at \(story.source)") {
                    if let link = story.link { safari = SafariLink(url: link) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ratioPage()
        .dynamicTypeSize(Self.sizes[sizeIndex])
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { textMenu }
        }
        .environment(\.openURL, OpenURLAction { url in
            safari = SafariLink(url: url)
            return .handled
        })
        .fullScreenCover(item: $safari) { SafariView(url: $0.url).ignoresSafeArea() }
        // Waits for the story (the news listener may still be loading), then its part.
        .task(id: story == nil ? nil : currentPart) { if story != nil { await load() } }
        .onAppear { NewsReading.markRead(storyId, in: &read) }
    }

    private var currentPart: String { part ?? story?.reader?.parts.first ?? "article" }

    private func load() async {
        failed = false
        article = nil
        do {
            article = try await NewsArticles.load(storyId: storyId, part: currentPart)
            resumeAt = NewsReading.position(storyId: storyId, part: currentPart)
        } catch {
            Logger(subsystem: "com.mg.ratio", category: "NewsReader").error("Couldn't load \(storyId, privacy: .public)/\(currentPart, privacy: .public): \(String(describing: error), privacy: .public)")
            failed = true
        }
    }

    private var textMenu: some View {
        Menu {
            Button { textSize = max(0, sizeIndex - 1) } label: { Label("Smaller text", systemImage: "textformat.size.smaller") }
                .disabled(sizeIndex <= 0)
            Button { textSize = min(Self.sizes.count - 1, sizeIndex + 1) } label: { Label("Larger text", systemImage: "textformat.size.larger") }
                .disabled(sizeIndex >= Self.sizes.count - 1)
            if textSize >= 0 {
                Button { textSize = -1 } label: { Label("Use the system size", systemImage: "arrow.uturn.backward") }
            }
            Toggle(isOn: $dyslexia) { Label("Dyslexia-friendly font", systemImage: "textformat") }
        } label: {
            Image(systemName: "textformat.size").accessibilityLabel("Text size and font")
        }
    }

    private func content(_ story: NewsStory, _ article: NewsArticle) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: RatioSpace.s) {
                header(story, article).id(-1)
                ForEach(Array(article.blocks.enumerated()), id: \.offset) { index, block in
                    NewsBlockView(block: block).id(index)
                }
                footer(story, article).id(article.blocks.count)
            }
            .scrollTargetLayout()
            .padding(RatioSpace.m)
            .ratioReadableWidth()
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $position, anchor: .top)
        .onChange(of: position) { _, index in
            if let index, index >= 0 { NewsReading.setPosition(index, storyId: storyId, part: currentPart) }
        }
        .task(id: resumeAt) {
            // Back to where the student left off, once the lazy stack has laid out.
            guard let index = resumeAt, index > 0 else { return }
            try? await Task.sleep(for: .milliseconds(150))
            proxy.scrollTo(min(index, article.blocks.count), anchor: .top)
            resumeAt = nil
        }
        }
    }

    private func header(_ story: NewsStory, _ article: NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("\(story.source) · \(story.publishedAt.formatted(.dateTime.day().month(.wide).year()))")
                .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            if currentPart == "judgment" {
                Text("Judgment").ratioFont(.monoLabel).foregroundStyle(Color.ratioOxblood)
            } else if currentPart == "summary" {
                Text("Press summary").ratioFont(.monoLabel).foregroundStyle(Color.ratioOxblood)
            }
            Text(story.title).ratioFont(.h1).accessibilityAddTraits(.isHeader)
            HStack(spacing: RatioSpace.xs) {
                if let byline = article.byline { Text(byline) }
                Text("\(max(1, article.words / 230)) min read")
            }
            .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Rectangle().fill(Color.ratioInk).frame(height: 1)
        }
        .padding(.bottom, RatioSpace.xs)
    }

    @ViewBuilder
    private func footer(_ story: NewsStory, _ article: NewsArticle) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.m) {
            if currentPart == "summary", story.reader?.parts.contains("judgment") == true {
                RatioButton("Read the full judgment →", style: .secondary) { part = "judgment" }
            } else if currentPart == "judgment", story.reader?.parts.contains("summary") == true {
                RatioButton("Back to the press summary", style: .tertiary) { part = "summary" }
            }
            if let why = story.whyItMatters {
                WhyItMattersBox(why: why) { navigator.push(.overview($0)) }
            }
            Rectangle().fill(Color.ratioRule).frame(height: 1)
            if let link = story.link {
                Button { safari = SafariLink(url: link) } label: {
                    Text("Read on \(story.source) →").ratioFont(.body).italic().underline().foregroundStyle(Color.ratioOxblood)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.ratioPress)
            }
            Text(article.licence).ratioFont(.caption).foregroundStyle(Color.ratioInk2)
        }
        .padding(.top, RatioSpace.m)
    }
}

/// One block, typeset in Ratio's styles.
private struct NewsBlockView: View {
    let block: NewsBlock

    @Environment(\.ratioDyslexiaFriendly) private var dyslexiaFriendly

    var body: some View {
        switch block {
        case .heading(let runs):
            Text(text(runs)).ratioFont(.h3).padding(.top, RatioSpace.s).accessibilityAddTraits(.isHeader)
        case .paragraph(let runs, let number):
            if let number {
                HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                    Text(number).ratioFont(.monoData).foregroundStyle(Color.ratioInk2).frame(minWidth: 28, alignment: .trailing)
                    Text(text(runs)).ratioFont(.body)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(text(runs)).ratioFont(.body)
            }
        case .quote(let runs):
            HStack(alignment: .top, spacing: RatioSpace.s) {
                Rectangle().fill(Color.ratioOxblood).frame(width: 2)
                Text(text(runs)).ratioFont(.body).italic()
            }
            .fixedSize(horizontal: false, vertical: true)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, runs in
                    HStack(alignment: .firstTextBaseline, spacing: RatioSpace.xs) {
                        Text(ordered ? "\(index + 1)." : "•").ratioFont(.body).foregroundStyle(Color.ratioInk2)
                        Text(text(runs)).ratioFont(.body)
                    }
                }
            }
        case .table(let rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: RatioSpace.s, verticalSpacing: RatioSpace.xs) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell).ratioFont(index == 0 ? .monoLabel : .small).frame(maxWidth: 240, alignment: .leading)
                            }
                        }
                        if index < rows.count - 1 { Divider().overlay(Color.ratioRule) }
                    }
                }
                .padding(RatioSpace.s)
            }
            .ratioPanel(padding: 0)
        case .image(let path, let alt):
            StorageImage(path: path)
                .accessibilityLabel(alt ?? "Image")
        }
    }

    /// Italic and bold runs, and links in oxblood (tapped links open in the reader's Safari sheet).
    private func text(_ runs: [NewsRun]) -> AttributedString {
        var out = AttributedString()
        for run in runs {
            var piece = AttributedString(run.t)
            if run.i == true { piece.font = RatioTypography.font(for: .bodyEmphasis, dyslexiaFriendly: dyslexiaFriendly) }
            if run.b == true { piece.inlinePresentationIntent = .stronglyEmphasized }
            if let href = run.href, let url = URL(string: href) {
                piece.link = url
                piece.foregroundColor = .ratioOxblood
                piece.underlineStyle = .single
            }
            out += piece
        }
        return out
    }
}

/// A lead image from Storage.
private struct StorageImage: View {
    let path: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous).fill(Color.ratioSunk).frame(height: 180)
            }
        }
        .task {
            guard let data = try? await Storage.storage().reference(withPath: path).data(maxSize: 3 * 1024 * 1024) else { return }
            image = UIImage(data: data)
        }
    }
}
