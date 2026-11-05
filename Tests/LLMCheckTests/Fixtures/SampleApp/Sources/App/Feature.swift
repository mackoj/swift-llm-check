import Foundation

@Reducer
struct Feature {
  @ObservableState
  struct State: Equatable {
    var count = 0
  }

  enum Action: ViewAction {
    case view(View)
    case delegate(Delegate)
  }

  func reduce() async {
    print("reduced")  // A violation for no-print.
  }
}
