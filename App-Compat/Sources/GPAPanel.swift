import SwiftUI
import AppKit
import JLUGateCore

/// 「GPA / 保研」：从登录邮箱前缀认出学院 + 年级，用户选一次专业，
/// 然后直接打开对应年级的计算器（不再先到网页首页选专业）。
struct GPAPanel: View {
    @Environment(AppModel.self) private var model

    @State private var pickerOpen = false
    @State private var query = ""
    @State private var showAll = false
    @State private var selectedMajor = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            collegeCard
            if let year = model.gpaYear {
                Text(Copy.f("GPA11", year))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            if model.gpaCollege != nil, !pickerOpen {
                majorPicker
            }
            openButton
            HStack(spacing: 8) {
                Button(Copy.t("GPA04")) {
                    NSWorkspace.shared.open(model.gpaURL)
                }
                .buttonStyle(.link)
                .font(.system(size: 9))
                Spacer(minLength: 0)
            }
            if model.gpaCollege != nil, !pickerOpen, !model.gpaMajors.isEmpty {
                Text(Copy.t("GPA12"))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { syncMajorSelection() }
        .onChange(of: model.gpaCollege?.code) { _, _ in syncMajorSelection() }
        .onChange(of: model.gpaYear) { _, _ in syncMajorSelection() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 15))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(Copy.t("GPA01"))
                    .font(.system(size: 13, weight: .semibold))
                Text(Copy.t("GPA02"))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 学院

    @ViewBuilder
    private var collegeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Copy.t("T08")).font(.caption).bold()

            if let college = model.gpaCollege {
                HStack(spacing: 6) {
                    Text(college.name)
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 4)
                    Button(pickerOpen ? Copy.t("GPA14") : Copy.t("T10")) {
                        pickerOpen.toggle()
                        if pickerOpen { query = "" }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                }
                HStack(spacing: 8) {
                    Text(sourceLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    if model.gpaCollegeSource == .manual {
                        Button(Copy.t("GPA06")) { model.clearGPACollege() }
                            .buttonStyle(.link)
                            .font(.system(size: 9))
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text(Copy.t("GPA10"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !pickerOpen {
                    Button(Copy.t("GPA07")) { pickerOpen = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            if pickerOpen {
                picker
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var picker: some View {
        TextField(Copy.t("T13"), text: $query)
            .textFieldStyle(.roundedBorder)
        let matches = GPACollegeDirectory.search(query)
        let shown = showAll ? matches : Array(matches.prefix(6))
        Text(countText(matches.count))
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        if matches.isEmpty {
            Text(Copy.t("T04"))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        ForEach(shown) { college in
            Button {
                model.setGPACollege(college)
                pickerOpen = false
                query = ""
                showAll = false
            } label: {
                HStack(spacing: 6) {
                    Text(college.name).font(.system(size: 11))
                    Spacer(minLength: 4)
                    Text(college.code)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        if matches.count > 6, !showAll {
            Button(Copy.f("T14", matches.count)) { showAll = true }
                .buttonStyle(.link)
                .font(.system(size: 10))
        }
    }

    private var sourceLabel: String {
        switch model.gpaCollegeSource {
        case .manual: Copy.t("GPA07")
        case .myCollege: Copy.t("GPA13")
        case .studentID: Copy.t("GPA08")
        case .account: Copy.t("GPA09")
        case nil: ""
        }
    }

    private func countText(_ total: Int) -> String {
        let all = GPACollegeDirectory.all.count
        if total == all { return Copy.f("T15", all) }
        if total > 6, !showAll { return Copy.f("T16", total) }
        return Copy.f("T17", total)
    }

    // MARK: 专业

    @ViewBuilder
    private var majorPicker: some View {
        let majors = model.gpaMajors
        if majors.isEmpty {
            Text(Copy.f("GPA16", model.gpaYear ?? 0))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                Text(Copy.t("GPA15"))
                    .font(.system(size: 10, weight: .semibold))
                Picker("", selection: $selectedMajor) {
                    Text(Copy.t("GPA17")).tag("")
                    ForEach(majors) { major in
                        Text(major.name).tag(major.name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer(minLength: 0)
            }
        }
    }

    private func syncMajorSelection() {
        let majors = model.gpaMajors
        if majors.count == 1 {
            selectedMajor = majors[0].name
        } else if !majors.contains(where: { $0.name == selectedMajor }) {
            selectedMajor = ""
        }
    }

    private var selectedPlanURL: URL? {
        guard !selectedMajor.isEmpty else { return nil }
        return model.gpaPlanURL(major: selectedMajor)
    }

    // MARK: 进计算器

    private var openButton: some View {
        Button {
            if let url = selectedPlanURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12, weight: .semibold))
                Text(Copy.t("GPA03"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedPlanURL == nil || pickerOpen)
        .opacity(selectedPlanURL == nil || pickerOpen ? 0.55 : 1)
    }
}
