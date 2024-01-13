import Combine
import CasePath
public typealias Effect<Action> = () -> Action
public typealias Reducer<Value, Action> = (inout Value, Action) -> [Effect<Action>]

public final class Store<Value, Action>: ObservableObject {
    private let reducer: Reducer<Value, Action>
    @Published public private(set) var value: Value
    private var cancellable: AnyCancellable?
    public init(
        initialValue: Value,
        reducer: @escaping Reducer<Value, Action>
    ) {
        self.value = initialValue
        self.reducer = reducer
    }
    
    public func send(_ action: Action) {
        reducer(&value, action).forEach {
            self.send($0())
        }
    }
    
    public func view<LocalValue, LocalAction>(
        value: @escaping (Value) -> LocalValue,
        action: CasePath<Action, LocalAction>
    ) -> Store<LocalValue, LocalAction> {
        let localStore = Store<LocalValue, LocalAction>(
            initialValue: value(self.value),
            reducer: { localValue, localAction in
                self.send(action.embed(localAction))
                localValue = value(self.value)
                return []
            }
        )
        localStore.cancellable = self.$value.sink { [weak localStore] newValue in
            localStore?.value = value(newValue)
        }
        return localStore
    }
}

public func pullback<
    LocalValue,
    GlobalValue,
    LocalAction,
    GlobalAction: CasePathable
>(
    _ reducer: @escaping Reducer<LocalValue, LocalAction>,
    value: WritableKeyPath<GlobalValue, LocalValue>,
    action: CasePath<GlobalAction, LocalAction>
) -> Reducer<GlobalValue, GlobalAction> {
    return { globalValue, globalAction in
        guard let localAction = action.extract(globalAction) 
        else { 
            return []
        }
        return reducer(
            &globalValue[keyPath: value],
            localAction
        )
        .map { effect in { action.embed(effect()) } }
    }
}

public func combine<Value, Action>(
    _ reducers: Reducer<Value, Action>...
) -> Reducer<Value, Action> {
    return { value, action in
        reducers.flatMap { reducer in
            reducer(&value, action)
        }
    }
}
