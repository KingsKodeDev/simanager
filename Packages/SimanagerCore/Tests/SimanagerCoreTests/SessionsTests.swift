import Foundation
import Testing
import SimanagerCore

@Test func cliSessionInZellij() {
    let s = owningSession(of: 25901, facts: facts())!                     // xcodebuild → zsh -c → claude
    #expect(s.pid == 25816 && s.kind == .claudeCLI && s.zellijTab == "acme")
    #expect(s.label == #"claude "acme" · zellij acme › acme · Ghostty"#)
}
@Test func desktopSession() {
    let s = owningSession(of: 77208, facts: facts())!
    #expect(s.kind == .claudeDesktop && s.label == #"claude desktop "simanager""#)
}
@Test func bareShellAndDaemon() {
    #expect(owningSession(of: 3100, facts: facts())!.label == "shell ttys008")
    #expect(owningSession(of: 7718, facts: facts()) == nil)
    #expect(owningSession(of: 15002, facts: facts()) == nil)
}
@Test func noTabMatchShowsPane() {      // facts with zellijTabs emptied
    #expect(owningSession(of: 25816, facts: facts(tabs: [:]))!.label == #"claude "acme" · zellij acme pane 1 · Ghostty"#)
}
@Test func candidatesAreClaudeAndTtyShells() {
    #expect(Set(sessionCandidatePIDs(parsePS(fixtureText("ps.txt")), sessionFiles: facts().sessionFiles)) == [25816, 77208, 2000, 3000, 3100])
}
