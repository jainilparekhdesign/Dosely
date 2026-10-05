import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @AppStorage(Prefs.activeProfileID) private var activeID = ""

    @State private var step = 0
    @State private var name = ""
    @State private var meals = MealTimes()
    @State private var agreed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if step > 0 {
                    Button { withAnimation { step -= 1 } } label: {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold)).padding(6)
                    }
                    .accessibilityLabel("Back")
                }
                ProgressView(value: Double(step + 1), total: 4)
            }
            .frame(height: 32)
            .padding(.horizontal, 24).padding(.top, 12)
            // Steps advance only via buttons, so the disclaimer can't be swiped past.
            Group {
                switch step {
                case 0: welcome
                case 1: about
                case 2: disclaimer
                default: notifications
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        }
        .animation(.easeInOut, value: step)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Steps

    private var welcome: some View {
        OnboardingPage(
            icon: "pills.circle.fill",
            title: "Your medicines, sorted",
            subtitle: "Scan a prescription and Dosely builds your daily schedule, reminds you on time, and keeps a record you can share with your doctor."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "doc.viewfinder", title: "Scan, check, done", text: "Reads printed and handwritten prescriptions — BD, TDS, 1-0-1, q8h and more.")
                FeatureRow(icon: "bell.badge", title: "Reminders you can act on", text: "Mark Taken, Snooze or Skip right from the notification.")
                FeatureRow(icon: "calendar", title: "A clear record", text: "See what was taken or missed and export a report.")
            }
        } footer: {
            Button("Get started") { step = 1 }.primaryButton()
        }
    }

    private var about: some View {
        OnboardingPage(
            icon: "fork.knife.circle.fill",
            title: "When do you usually eat?",
            subtitle: "Doses like “after breakfast” are timed from your meals. You can change these any time."
        ) {
            VStack(spacing: 0) {
                TextField("Your name", text: $name)
                    .textContentType(.givenName)
                    .font(.title3)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.bottom, 16)
                MealTimesEditor(meals: $meals)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        } footer: {
            Button("Continue") { step = 2 }.primaryButton()
        }
    }

    private var disclaimer: some View {
        OnboardingPage(
            icon: "stethoscope.circle.fill",
            title: "Before we begin",
            subtitle: "Dosely helps you follow your prescription. It isn't a doctor."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "exclamationmark.shield", title: "No medical advice", text: "Dosely does not give dosage advice or check drug interactions. Always follow your doctor's or pharmacist's instructions.")
                FeatureRow(icon: "eye", title: "Always check the scan", text: "Scans can misread handwriting. Nothing is saved until you review and confirm it.")
                FeatureRow(icon: "lock", title: "Private by design", text: "Your data stays on this iPhone. Prescriptions are read on-device. We never sell data or show ads.")
                Toggle(isOn: $agreed) {
                    Text("I understand Dosely doesn't replace my doctor's advice").font(.subheadline.weight(.medium))
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        } footer: {
            Button("I agree") { step = 3 }.primaryButton().disabled(!agreed)
        }
    }

    private var notifications: some View {
        OnboardingPage(
            icon: "bell.circle.fill",
            title: "Never miss a dose",
            subtitle: "Allow notifications so Dosely can remind you at each dose time — even with no internet. You can mark doses taken straight from the reminder."
        ) {
            NotificationPreview()
        } footer: {
            VStack(spacing: 10) {
                Button("Turn on reminders") {
                    Task {
                        _ = await NotificationService.shared.requestAuthorization()
                        finish()
                    }
                }.primaryButton()
                Button("Not now") { finish() }.font(.body.weight(.medium))
            }
        }
    }

    private func finish() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let profile = Profile(name: trimmed.isEmpty ? "Me" : trimmed, relationship: "Me", isPrimary: true)
        profile.mealTimes = meals
        context.insert(profile)
        try? context.save()
        activeID = profile.id.uuidString
        withAnimation { onboarded = true }
    }
}

private struct OnboardingPage<Content: View, Footer: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: icon)
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.top, 32)
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).font(.body).foregroundStyle(.secondary)
                    content.padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct NotificationPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                PillIconView(type: .tablet, shape: .round, colorHex: "#FFFFFF", size: 40)
                    .frame(width: 44, height: 44)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metformin 500 mg").font(.subheadline.weight(.semibold))
                    Text("Take 1 tablet · after food").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("now").font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            HStack(spacing: 8) {
                ForEach(["Taken", "Snooze 10 min", "Skip"], id: \.self) { t in
                    Text(t).font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example reminder with Taken, Snooze and Skip buttons")
    }
}

extension View {
    func primaryButton() -> some View {
        buttonStyle(PrimaryButtonStyle())
    }
}

/// Full-width, high-contrast button used for the main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(isEnabled ? Color.accentColor : Color.gray.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Four meal-time pickers, shared by onboarding and settings.
struct MealTimesEditor: View {
    @Binding var meals: MealTimes

    var body: some View {
        VStack(spacing: 0) {
            row("Breakfast", "sunrise", \.breakfast)
            Divider().padding(.leading, 52)
            row("Lunch", "sun.max", \.lunch)
            Divider().padding(.leading, 52)
            row("Dinner", "sunset", \.dinner)
            Divider().padding(.leading, 52)
            row("Bedtime", "moon.zzz", \.bedtime)
        }
    }

    private func row(_ title: String, _ icon: String, _ key: WritableKeyPath<MealTimes, Int>) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 28)
            Text(title)
            Spacer()
            DatePicker(title, selection: Binding(
                get: { Fmt.date(fromMinutes: meals[keyPath: key]) },
                set: { meals[keyPath: key] = Fmt.minutes(from: $0) }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}
