import Testing
@testable import __Feature__Feature

/// OPTIONAL. Only when `__Feature__StateMaker.swift` exists. StateMakers are pure, so test them
/// with table-style cases and no dependencies.
@MainActor
struct __Feature__StateMakerTests {
    @Test("""
        Given no user name,
        When the state is made,
        Then the generic title is used
        """)
    func makeWithoutUserNameUsesTitle() {
        let state = __Feature__StateMaker.make(.init(userName: nil))

        #expect(state == __Feature__ViewState())
    }

    @Test("""
        Given a user name,
        When the state is made,
        Then the title greets the user
        """)
    func makeWithUserNameGreets() {
        let state = __Feature__StateMaker.make(.init(userName: "Alex"))

        #expect(state.title != __Feature__ViewState().title)
        #expect(state.title.contains("Alex"))
    }
}
