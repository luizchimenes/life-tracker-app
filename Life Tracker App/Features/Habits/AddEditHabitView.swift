import SwiftData
import SwiftUI

struct AddEditHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let habit: Habit?

    @State private var name: String
    @State private var notes: String
    @State private var iconName: String
    @State private var colorName: String
    @State private var scheduleType: HabitScheduleType
    @State private var weekdays: Set<Int>
    @State private var startDate: Date
    @State private var errorMessage: String?

    init(habit: Habit? = nil) {
        self.habit = habit
        _name = State(initialValue: habit?.name ?? "")
        _notes = State(initialValue: habit?.notes ?? "")
        _iconName = State(initialValue: habit?.iconName ?? "checkmark.circle")
        _colorName = State(initialValue: habit?.colorName ?? CategoryColorName.blue.rawValue)
        _scheduleType = State(initialValue: habit?.schedule.type ?? .daily)
        _weekdays = State(initialValue: habit?.schedule.weekdays ?? [])
        _startDate = State(initialValue: habit?.startDate ?? .now)
    }

    private var schedule: HabitSchedule {
        HabitSchedule(type: scheduleType, weekdays: scheduleType == .weekly ? weekdays : [])
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && schedule.isValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Picker("Frequency", selection: $scheduleType) {
                        ForEach(HabitScheduleType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if scheduleType == .weekly {
                        WeekdayPicker(selection: $weekdays)
                        if weekdays.isEmpty {
                            Label("Choose at least one day of the week.", systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }

                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                } header: {
                    Text("Frequency")
                } footer: {
                    if habit != nil {
                        Text("Schedule changes apply from today on. Past days keep the schedule they had, so your history is not rewritten.")
                    }
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(HabitFormatting.icons, id: \.self) { icon in
                            Button {
                                iconName = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(icon == iconName ? .white : Color.category(named: colorName))
                                    .background(icon == iconName ? Color.category(named: colorName) : Color.clear, in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(icon.replacingOccurrences(of: ".", with: " ")))
                            .accessibilityAddTraits(icon == iconName ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CategoryColorName.allCases) { color in
                            Button {
                                colorName = color.rawValue
                            } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if color.rawValue == colorName {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(color.rawValue))
                            .accessibilityAddTraits(color.rawValue == colorName ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(habit == nil ? "New Habit" : "Edit Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .alert("Unable to Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            if let habit {
                try HabitService.update(
                    habit,
                    name: name,
                    notes: notes,
                    iconName: iconName,
                    colorName: colorName,
                    schedule: schedule,
                    startDate: startDate,
                    in: modelContext
                )
            } else {
                try HabitService.create(
                    name: name,
                    notes: notes,
                    iconName: iconName,
                    colorName: colorName,
                    schedule: schedule,
                    startDate: startDate,
                    in: modelContext
                )
            }
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

/// Seven toggles in the calendar's own week order, with localized names.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HabitFormatting.orderedWeekdays(), id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    if isOn {
                        selection.remove(weekday)
                    } else {
                        selection.insert(weekday)
                    }
                } label: {
                    Text(HabitFormatting.veryShortName(weekday))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isOn ? .white : .primary)
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(HabitFormatting.fullName(weekday)))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
    }
}
