import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct ProofreadingSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Section {
			Label {
				Toggle(
					"Local Proofreading",
					isOn: Binding(
						get: { store.hexSettings.localProofreadingEnabled },
						set: { store.send(.setLocalProofreadingEnabled($0)) }
					)
				)
			} icon: {
				Image(systemName: "checkmark.text.clipboard")
			}

			if store.hexSettings.localProofreadingEnabled {
				TextField(
					"Endpoint URL",
					text: Binding(
						get: { store.hexSettings.localProofreadingBaseURL },
						set: { store.send(.setLocalProofreadingBaseURL($0)) }
					)
				)

				TextField(
					"Model",
					text: Binding(
						get: { store.hexSettings.localProofreadingModel },
						set: { store.send(.setLocalProofreadingModel($0)) }
					)
				)

				Text("Selected text is sent only to this OpenAI-compatible endpoint (for example Ollama on your Jetson). Nothing leaves your network.")
					.settingsCaption()
			}
		} header: {
			Text("Proofreading")
		}
		.enableInjection()
	}
}
