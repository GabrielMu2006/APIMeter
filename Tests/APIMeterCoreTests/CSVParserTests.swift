import Foundation
import Testing
import Foundation
import APIMeterCore

struct CSVParserTests {

    @Test func parsesSimpleRows() {
        let rows = CSVParser.parse("a,b,c\n1,2,3\n")
        #expect(rows.count == 2)
        #expect(rows[0] == ["a", "b", "c"])
        #expect(rows[1] == ["1", "2", "3"])
    }

    @Test func handlesQuotedFieldsAndCRLF() {
        let rows = CSVParser.parse("a,b,c\r\n\"x,y\",2,\"line\nbreak\"\r\n")
        #expect(rows.count == 2)
        #expect(rows[1][0] == "x,y")
        #expect(rows[1][2] == "line\nbreak")
    }

    @Test func handlesEscapedQuotes() {
        let rows = CSVParser.parse("\"say \"\"hi\"\"\",ok\n")
        #expect(rows[0][0] == "say \"hi\"")
    }

    @Test func stripsBOMAndEmptyLines() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("h1,h2\n1,2\n\n".utf8)
        let rows = try? CSVParser.parse(data: data)
        #expect(rows?.count == 2)
        #expect(rows?.first?.first == "h1")
    }

    @Test func rejectsNonUTF8() {
        let data = Data([0xFF, 0xFE, 0x00, 0x41])  // UTF-16 LE bytes
        #expect(throws: CSVParseError.self) {
            try CSVParser.parse(data: data)
        }
    }
}
