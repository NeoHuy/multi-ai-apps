import MultiAICore
import Observation

@MainActor
@Observable
final class AppUIState {
    var showingAddSheet: Bool = false
    var preselectedApp: InstalledApp?
    var preselectedURL: String?

    func openAddAccount(app: InstalledApp? = nil, url: String? = nil) {
        preselectedApp = app
        preselectedURL = url
        showingAddSheet = true
    }
}
