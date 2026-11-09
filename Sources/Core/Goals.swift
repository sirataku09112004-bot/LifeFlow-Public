import Foundation

struct FlowGoal: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var deadline: Date
    var steps: [FlowSubtask] = []
    var isDone = false

    var completedSteps: Int { steps.filter(\.isDone).count }
    var progress: Double {
        steps.isEmpty ? (isDone ? 1 : 0) : Double(completedSteps) / Double(steps.count)
    }
}

extension FlowData {
    var annualGoals: [FlowGoal] {
        get { goals ?? [] }
        set { goals = newValue }
    }

    func todoForGoalStep(_ stepID: UUID, goalID: UUID, today: Date) -> FlowTask? {
        guard !tasks.contains(where: { $0.goalStepID == stepID }),
              let goal = annualGoals.first(where: { $0.id == goalID && !$0.isDone }),
              let step = goal.steps.first(where: { $0.id == stepID && !$0.isDone }) else { return nil }
        return FlowTask(title: step.title, day: today, goalStepID: step.id)
    }
}
