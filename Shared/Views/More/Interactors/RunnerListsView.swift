//
//  RunnerListsView.swift
//  Suwatte (iOS)
//
//  Created by Mantton on 2022-08-07.
//

import Alamofire
import Kingfisher
import Nuke
import NukeUI
import RealmSwift
import SwiftUI

struct RunnerListsView: View {
    @State var presentAlert = false
    @ObservedResults(StoredRunnerList.self) var runnerLists
    @AppStorage(STTKeys.AppAccentColor) var color: Color = .sttDefault
    var body: some View {
        List {
            
            ForEach(runnerLists) { list in
                NavigationLink {
                    RunnerListInfo(listURL: list.url)
                        .navigationTitle(list.listName ?? list.url)
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack {
                        Text(list.listName ?? list.url)
                        Spacer()
                        if list.hosted {
                            Image(systemName: "globe")
                                .foregroundColor(color)
                        }
                    }
                    
                }
            }
            .onDelete(perform: $runnerLists.remove(atOffsets:))
        }
        .navigationTitle("Saved Runner Lists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("\(Image(systemName: "plus"))") {
                    presentAlert.toggle()
                }
            }
        }
        .onChange(of: presentAlert) { newValue in
            if newValue {
                promptURL()
            }
        }
    }
}

extension RunnerListsView {
    func handleSubmit(url: String) async {
        if url.isEmpty { return }
        do {
            try await DaisukeEngine.shared.saveRunnerList(at: url)
            DispatchQueue.main.async {
                ToastManager.shared.display(.info("Saved Runner!"))
            }
        } catch {
            DispatchQueue.main.async {
                ToastManager.shared.display(.error(error))
            }
        }
        presentAlert = false
    }

    func promptURL() {
        let ac = UIAlertController(title: "Enter List URL", message: "Suwatte will automatically parse valid URLS.", preferredStyle: .alert)
        ac.addTextField()
        let field = ac.textFields![0]
        field.autocorrectionType = .no
        field.keyboardType = .URL
        let submitAction = UIAlertAction(title: "Submit", style: .default) { [unowned ac] _ in
            let field = ac.textFields?.first
            guard let text = field?.text else {
                return
            }
            Task {
                await handleSubmit(url: text)
            }
        }
        ac.addAction(.init(title: "Cancel", style: .cancel, handler: { _ in
            presentAlert = false
        }))
        ac.addAction(submitAction)

        KEY_WINDOW?.rootViewController?.present(ac, animated: true)
    }
}

extension RunnerListsView {
    struct RunnerListInfo: View {
        var listURL: String
        @State var loadable: Loadable<RunnerList> = .idle
        var body: some View {
            LoadableView(loadable: loadable) {
                ProgressView()
                    .task {
                        await load()
                    }
            } _: {
                ProgressView()
            } _: { error in
                ErrorView(error: error) {
                    Task {
                        await load()
                    }
                }
                .onAppear {
                    print(error)
                }
            } _: { value in
                InternalListInfoView(list: value, listURL: listURL)
            }
            .animation(.default, value: loadable)
            .refreshable {
                loadable = .idle
            }
        }

        @MainActor
        func load() async {
            loadable = .loading
            do {
                guard let url = URL(string: listURL) else {
                    throw DaisukeEngine.Errors.NamedError(name: "Parse Error", message: "Invalid URL")
                }
                let data = try await DaisukeEngine.shared.getRunnerList(at: url)

                loadable = .loaded(data)
                DataManager.shared.saveRunnerList(data, at: url)

            } catch {
                loadable = .failed(error)
            }
        }
    }

    struct InternalListInfoView: View {
        var list: RunnerList
        var listURL: String
        var body: some View {
            List {
                ForEach(list.runners, id: \.self) { runner in
                    RunnerListInfo.RunnerListCell(listURL: listURL, list: list, runner: runner)
                        .frame(height: 75)
                }
            }
        }
    }
}

extension RunnerListsView.RunnerListInfo {
    struct RunnerListCell: View {
        @State var isLoading = false
        @ObservedObject var engine = DaisukeEngine.shared
        var listURL: String
        var list: RunnerList
        var runner: Runner
        var body: some View {
            let runnerState = getRunnerState(runner: runner)

            HStack {
                RunnerHeader(runner: runner)
                Spacer()
                Button {
                    Task { @MainActor in
                        isLoading = true
                        if (list.hosted ?? false ) {
                            engine.saveHostedRunner(list: listURL, runner: runner)
                        } else {
                            await saveExternalRunnerList()
                        }
                        isLoading = false
                    }
                } label: {
                    Group {
                        if !isLoading {
                            Text(runnerState.description)
                        } else {
                            ProgressView()
                        }
                    }
                    .font(.footnote.weight(.bold))
                    .padding(.all, 5)
                    .foregroundColor(.primary)
                    .background(Color.fadedPrimary)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(runnerState.noInstall)
            }
        }

        enum RunnerState {
            case installed, outdated, sourceOutdated, notInstalled, appOutDated

            var description: String {
                switch self {
                case .installed:
                    return "REFRESH"
                case .outdated:
                    return "UPDATE"
                case .sourceOutdated:
                    return "OUTDATED"
                case .notInstalled:
                    return "GET"
                case .appOutDated:
                    return "UPDATE APP"
                }
            }

            var noInstall: Bool {
                self == .appOutDated || self == .sourceOutdated
            }
        }
        
        func saveExternalRunnerList() async {
            let base = URL(string: listURL)!

            let url = base
                .appendingPathComponent("runners")
                .appendingPathComponent("\(runner.path).stt")
            do {
                try await DaisukeEngine.shared.importRunner(from: url)
                DataManager.shared.saveRunnerInfomation(runner: runner, at: base)
                ToastManager.shared.info("\(runner.name) Loaded!")
            } catch {
                ToastManager.shared.display(.error(error))
            }

        }
        func getRunnerState(runner: Runner) -> RunnerState {
            if let minVer = runner.minSupportedAppVersion, let appVersion = Bundle.main.releaseVersionNumber {
                let result = minVer.compare(appVersion)
                if ![ComparisonResult.orderedSame, .orderedAscending].contains(result) {
                    return .appOutDated
                }
            }
            guard let installed = engine.getSource(with: runner.id) else {
                return .notInstalled
            }
            if installed.version > runner.version {
                return .sourceOutdated
            } else if installed.version == runner.version {
                return .installed
            } else {
                return .outdated
            }
        }

        func RunnerHeader(runner: Runner) -> some View {
            HStack {
                STTThumbView(url: runner.getThumbURL(in: listURL))
                    .frame(width: 44, height: 44)
                    .cornerRadius(7)
                VStack(alignment: .leading, spacing: 5) {
                    Text(runner.name)
                        .fontWeight(.semibold)
                    HStack {
                        Text("v\(runner.version.description)")

                        if runner.primarilyAdultContent ?? false {
                            Text("18+")
                                .bold()
                                .padding(.all, 2)
                                .background(Color.red.opacity(0.3))
                                .cornerRadius(5)
                        }
                    }
                    .font(.footnote.weight(.light))
                    Text("Content Source")
                        .font(.footnote.weight(.ultraLight))
                }
            }
            .frame(height: 70, alignment: .center)
        }
    }
}

extension RunnerListsView {
    struct AddSheet: View {
        @State var listURL: String = ""
        @Binding var presenting: Bool
        var body: some View {
            VStack(alignment: .leading, spacing: 15) {
                Text("Add List")
                    .font(.headline)
                HStack {
                    Image(systemName: "list.star")
                    TextField("List URL", text: $listURL)
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .autocapitalization(.none)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 15)
                .background(Color.fadedPrimary)
                .cornerRadius(7)
            }
            .toast()
            .onSubmit(of: .text) {
                Task {
                    await handleSubmit(url: listURL)
                }
            }
            .padding(.horizontal)
            .navigationTitle("Add New List")
        }

        func handleSubmit(url: String) async {
            if url.isEmpty { return }
            do {
                try await DaisukeEngine.shared.saveRunnerList(at: url)
                DispatchQueue.main.async {
                    ToastManager.shared.display(.info("Saved Runner!"))
                    presenting.toggle()
                }

            } catch {
                DispatchQueue.main.async {
                    ToastManager.shared.display(.error(error))
                }
            }
        }
    }
}

extension DaisukeEngine {
    func getRunnerList(at url: URL) async throws -> RunnerList {
        let listUrl = url.lastPathComponent == "runners.json" ? url : url.runnersListURL
        let req = URLRequest(url: listUrl, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        let task = AF.request(req).validate().serializingDecodable(RunnerList.self)

        let runnerList = try await task.value
        return runnerList
    }

    // Get Source List Info
    func saveRunnerList(at url: String) async throws {
        // Get runner list
        let base = URL(string: url)
        guard let base else {
            throw Errors.NamedError(name: "", message: "Invalid URL")
        }
        let url = base.runnersListURL
        let runnerList = try await getRunnerList(at: url)
        await MainActor.run(body: {
            let realm = try! Realm()
            let obj = StoredRunnerList()
            obj.listName = runnerList.listName
            obj.url = base.absoluteString
            obj.hosted = runnerList.hosted ?? false
            try! realm.safeWrite {
                realm.add(obj, update: .modified)
            }
        })
    }
}


extension URL {
    
    var runnersListURL: URL {
        self.appendingPathComponent("runners.json")
    }
}
