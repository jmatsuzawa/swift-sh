import Testing

@testable import swift_sh

@Test(arguments: [
    ("ls", ["ls"]),
    ("ls /tmp", ["ls", "/tmp"]),
    ("ls /tmp > foo", ["ls", "/tmp", ">", "foo"]),
    ("cat < foo", ["cat", "<", "foo"]),
    ("   cat   <   foo   ", ["cat", "<", "foo"]),
    ("ls\t/tmp", ["ls", "/tmp"]),
])
func TestTokenize(_ input: String, _ expected: [String]) {
    let actual = tokenize(input)

    #expect(actual == expected)
}

@Test(arguments: [
    (["ls"], [Element.command("ls", [])]),
    (["ls", "/tmp"], [.command("ls", ["/tmp"])]),
    (["foo", "|", "bar"], [.command("foo", []), .pipe, .command("bar", [])]),
    (["foo", "<", "bar"], [.command("foo", []), .redirectIn("bar")]),
    (["foo", ">", "bar"], [.command("foo", []), .redirectOut("bar")]),
])
func testParse(_ tokens: [String], _ expected: [Element]) {
    let actual = try! parseTokens(tokens)
    #expect(actual == expected)
}

@Test(arguments: [
    (["|", "ls"], ShellError.syntaxError),
    (["<", "ls"], .syntaxError),
    ([">", "ls"], .syntaxError),
    (["ls", "|"], .syntaxError),
    (["ls", "<"], .syntaxError),
    (["ls", ">"], .syntaxError),
    (["ls", "<", "foo", "<", "bar"], .syntaxError),
    (["ls", ">", "foo", ">", "bar"], .syntaxError),
    (["foo", "|", "|", "bar"], .syntaxError),
    (["foo", "|", ">", "bar"], .syntaxError),
    (["foo", "|", "<", "bar"], .syntaxError),
    (["foo", "<", "|", "bar"], .syntaxError),
    (["foo", "<", ">", "bar"], .syntaxError),
    (["foo", "<", "<", "bar"], .syntaxError),
    (["foo", ">", "|", "bar"], .syntaxError),
    (["foo", ">", ">", "bar"], .syntaxError),
    (["foo", ">", "<", "bar"], .syntaxError),
    (["foo", "<", "bar", "baz"], .syntaxError),
    (["foo", ">", "bar", "baz"], .syntaxError),
])
func testParseError(_ tokens: [String], _ expected: ShellError) {
    #expect(throws: expected) {
        try parseTokens(tokens)
    }
}
