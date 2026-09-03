import AppKit
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("MenuBarDashboardButtonPresenterTests", .serialized)
@MainActor
struct MenuBarDashboardButtonPresenterTests {
    @Test func presentInstallsTemplateImageAndPreservesButtonBehavior() throws {
        let button = button(height: 24)
        let target = NSObject()
        let action = #selector(NSObject.description)
        button.target = target
        button.action = action
        var length: CGFloat = 0
        let presenter = MenuBarDashboardButtonPresenter(
            button: button,
            width: { 240 },
            setLength: { length = $0 }
        )

        presenter.present(result())

        let image = try #require(button.image)
        #expect(image.isTemplate)
        #expect(button.imagePosition == .imageOnly)
        #expect(button.imageScaling == .scaleNone)
        #expect(button.title.isEmpty)
        #expect(button.toolTip == "CPU 24%")
        #expect(button.accessibilityLabel() == "CPU 24%")
        #expect(button.target === target)
        #expect(button.action == action)
        #expect(length >= image.size.width + MenuBarDashboardTwoLineLayout.chrome)
        #expect(length <= 240)
    }

    @Test func validationFailureUsesTextThenTinyBudgetUsesAccessibleIconThenImageReturns() throws {
        let button = button(height: 24)
        var budget = 240.0
        var validationFails = true
        let presenter = MenuBarDashboardButtonPresenter(
            button: button,
            width: { budget },
            setLength: { _ in },
            validateImage: { _ in !validationFails }
        )

        presenter.present(result())
        #expect(button.image == nil)
        #expect(button.title == "CPU 24%")
        #expect(button.toolTip == "CPU 24%")
        #expect(button.accessibilityLabel() == "CPU 24%")

        budget = 1
        presenter.present(result())
        #expect(button.title.isEmpty)
        #expect(button.image?.accessibilityDescription == "Needlbar")
        #expect(button.accessibilityLabel() == "Needlbar")

        validationFails = false
        budget = 240
        presenter.present(result())
        #expect(button.image?.isTemplate == true)
        #expect(button.title.isEmpty)
    }

    @Test func insufficientHeightUsesMeasuredTextFallback() {
        let button = button(height: 12)
        let presenter = MenuBarDashboardButtonPresenter(button: button, width: { 240 }, setLength: { _ in })

        presenter.present(result())

        #expect(button.image == nil)
        #expect(button.title == "CPU 24%")
        #expect(button.accessibilityLabel() == "CPU 24%")
    }

    @Test func identicalPresentationDoesNotReplaceInstalledImageButGeometryChangesDo() throws {
        let button = button(height: 24)
        var lengthAssignments = 0
        var geometry = MenuBarDashboardButtonPresenter.Geometry(
            bounds: button.bounds.size, budget: 240, scale: 2, appearance: .aqua
        )
        let presenter = MenuBarDashboardButtonPresenter(
            button: button,
            width: { 240 },
            setLength: { _ in lengthAssignments += 1 },
            geometry: { geometry }
        )

        presenter.present(result())
        let original = try #require(button.image)
        presenter.present(result())
        #expect(button.image === original)
        #expect(lengthAssignments == 1)

        geometry = .init(bounds: button.bounds.size, budget: 239, scale: 2, appearance: .aqua)
        presenter.present(result())
        #expect(button.image !== original)
    }

    @Test func heightBudgetScaleAndAppearanceChangesReplaceTheInstalledImage() throws {
        let button = button(height: 24)
        var geometry = MenuBarDashboardButtonPresenter.Geometry(
            bounds: button.bounds.size, budget: 240, scale: 2, appearance: .aqua
        )
        let presenter = MenuBarDashboardButtonPresenter(
            button: button,
            width: { 240 },
            setLength: { _ in },
            geometry: { geometry }
        )

        presenter.present(result())
        let first = try #require(button.image)

        button.frame.size.height = 25
        geometry = .init(bounds: button.bounds.size, budget: 240, scale: 2, appearance: .aqua)
        presenter.present(result())
        let heightImage = try #require(button.image)
        #expect(heightImage !== first)

        geometry = .init(bounds: button.bounds.size, budget: 239, scale: 2, appearance: .aqua)
        presenter.present(result())
        let budgetImage = try #require(button.image)
        #expect(budgetImage !== heightImage)

        geometry = .init(bounds: button.bounds.size, budget: 239, scale: 1, appearance: .aqua)
        presenter.present(result())
        let scaleImage = try #require(button.image)
        #expect(scaleImage !== budgetImage)

        geometry = .init(bounds: button.bounds.size, budget: 239, scale: 1, appearance: .darkAqua)
        presenter.present(result())
        #expect(button.image !== scaleImage)
    }

    @Test func frameChangeRefreshesCurrentPresentationAndReleasedPresenterDoesNotRetainObservers() async throws {
        let button = button(height: 24)
        var budget = 240.0
        weak var weakPresenter: MenuBarDashboardButtonPresenter?
        var presenter: MenuBarDashboardButtonPresenter? = .init(button: button, width: { budget }, setLength: { _ in })
        weakPresenter = presenter
        presenter?.present(result())
        let first = try #require(button.image)

        budget = 80
        button.frame.size.width = 80
        for _ in 0..<10 { await Task.yield() }
        #expect(button.image !== first || button.title != "")

        presenter = nil
        #expect(weakPresenter == nil)
    }

    @Test func textFallbackIncludesChromeAndNeverAllocatesPastBudget() {
        let button = button(height: 12)
        var assigned: CGFloat = 0
        let presenter = MenuBarDashboardButtonPresenter(button: button, width: { 70 }, setLength: { assigned = $0 })

        presenter.present(result())

        #expect(button.title == "CPU 24%")
        #expect(assigned <= 70)
        #expect(assigned >= MenuBarDashboardTwoLineLayout.chrome)
    }

    @Test func textFallbackNeedsItsMeasuredWidthAndChrome() {
        let button = button(height: 12)
        let font = NSFont.menuFont(ofSize: 0)
        let exact = ceil(("CPU 24%" as NSString).size(withAttributes: [.font: font]).width + MenuBarDashboardTwoLineLayout.chrome)
        var budget = Double(exact - 1)
        var assigned: CGFloat = 0
        let presenter = MenuBarDashboardButtonPresenter(button: button, width: { budget }, setLength: { assigned = $0 })

        presenter.present(result())
        #expect(button.title.isEmpty)
        #expect(assigned == 22)

        budget = Double(exact)
        presenter.present(result())
        #expect(button.title == "CPU 24%")
        #expect(assigned == exact)
    }

    @Test func imageLengthNeverRoundsPastItsFractionalBudget() throws {
        let button = button(height: 24)
        let dashboard = result()
        let layout = try #require(MenuBarDashboardTwoLineLayout.fit(
            segments: dashboard.segments, width: 240, height: 24, scale: 2
        ))
        let budget = Double(layout.size.width + MenuBarDashboardTwoLineLayout.chrome + 0.25)
        var assigned: CGFloat = 0
        let presenter = MenuBarDashboardButtonPresenter(
            button: button,
            width: { budget },
            setLength: { assigned = $0 }
        )

        presenter.present(dashboard)

        #expect(button.image != nil)
        #expect(assigned <= CGFloat(budget))
    }

    private func button(height: CGFloat) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 240, height: height))
        button.isBordered = false
        return button
    }

    private func result() -> MenuBarDashboardRenderResult {
        .init(
            layout: .compact,
            title: "CPU 24%",
            moduleIDs: [.cpu],
            tooltip: "CPU 24%",
            segments: [.init(.cpu, label: "CPU", primary: .init("24%", samples: ["100%", "—"]))],
            textCandidates: ["CPU 24%"]
        )
    }
}
