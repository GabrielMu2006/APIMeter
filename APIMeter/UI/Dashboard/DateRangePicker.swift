import SwiftUI

/// 7D / 30D / Month / Custom selector (spec 37). Default: 30 Days.
struct DateRangePicker: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 12) {
            Picker("Range", selection: $viewModel.preset) {
                ForEach(DashboardViewModel.RangePreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if viewModel.preset == .custom {
                DatePicker("From", selection: $viewModel.customStart, displayedComponents: .date)
                    .datePickerStyle(.field)
                DatePicker("To", selection: $viewModel.customEnd, displayedComponents: .date)
                    .datePickerStyle(.field)
            }

            Spacer()
        }
        .onChange(of: viewModel.preset) {
            Task { await viewModel.reload() }
        }
        .onChange(of: viewModel.customStart) {
            Task { await viewModel.reload() }
        }
        .onChange(of: viewModel.customEnd) {
            Task { await viewModel.reload() }
        }
    }
}
