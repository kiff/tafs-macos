import Foundation

private let session = Session(accessToken: "tok", expiresIn: 60, tenant: "t1", subject: "u1", deviceID: nil)

let doorPage = #"""
{"doors":[{"id":"d1","app":"email","kind":"email","label":"Email","open":true,"address":"refunds@tafs.example","proof":"proven","how":"It checks the sender's server signed the message","keys":[{"id":"you@acme.example","auto":true},{"id":"ana@acme.example","name":"Ana"},{"id":"bo@acme.example","name":7}],"today":3,"limit":20,"resting":false,"others_today":1,"others_limit":10,"words":{"state":"Open · 3 of 20 today","tap":"Click to close it","settings":"Its settings are below"}}],
 "apps":[{"id":"email","label":"Email","kind":"email","proof":"proven","how":"Checks the sender"},{"id":"whatsapp","label":"WhatsApp","kind":"whatsapp","proof":"proven","how":"Checks the number"},{"id":"sms","label":"SMS","kind":"sms","proof":"none","how":"Can't tell"}],
 "knocks":[{"id":"k1","door":"d1","app":"email","from":"mara@customer.example","name":"Mara","proof":"pass","subject":"Refund","text":"Hi","at":"2026-11-15T10:00:00Z"},
           {"id":"k2","door":"d1","app":"email","from":"x@y.example","at":"2026-11-15T10:05:00Z","state":"done","rest":"keys","dropped":2,"paired":true}]}
"""#

private func cloud(_ answers: [(Int, String)]) -> (CloudClient, CannedTransport) {
    let transport = CannedTransport(answers)
    return (CloudClient(transport: transport, session: session), transport)
}

private func json(_ data: Data) throws -> NSDictionary? { try JSONSerialization.jsonObject(with: data) as? NSDictionary }

let tafDoorsTests: [Test] = [
    Test("a taf's doors read as the iPad reads them: what's missing defaults, what must be there must", awaiting: {
        let (client, transport) = cloud([(200, doorPage), (200, #"{"doors":[],"apps":[],"knocks":[{"id":"k","door":"d","app":"email","from":"a"}]}"#)])
        let page = try await client.doors(of: "taf-1")
        try expectEqual(transport.sent[0].method + " " + transport.sent[0].path, "GET /v1/tafs/taf-1/doors")
        let door = page.doors[0]
        try expectEqual(door.holdsKeys, true)
        try expectEqual(door.keys.map(\.id), ["you@acme.example", "ana@acme.example", "bo@acme.example"])
        try expectEqual(door.keys.map(\.name), [nil, "Ana", nil])
        try expectEqual(door.keys.map(\.auto), [true, false, false])
        try expectEqual(door.words?.tap, "Click to close it")
        try expectEqual(door.othersLimit, 10)
        try expectEqual(page.knocks[0].state, "open")
        try expectEqual(page.knocks[0].who, "Mara (mara@customer.example)")
        try expectEqual(page.knocks[1].isLine, true)
        try expectEqual(page.knocks[1].text, "")
        try expectEqual(page.knocks[1].proof, "none")
        try expectEqual(page.knocks[1].paired, true)
        // A knock without its time doesn't read, and the doors with it.
        let missing = try? await client.doors(of: "taf-1")
        try expect(missing == nil, "a knock without `at`")
    }),
    Test("each change to a door is tafs cloud's route with its exact body, answered with the door", awaiting: {
        let door = #"{"door":{"id":"d1","app":"email","kind":"email","label":"Email","open":false,"address":"a@t.example","proof":"proven","how":"h","keys":[],"today":0,"limit":20,"resting":false}}"#
        let (client, transport) = cloud([(200, door), (200, door), (200, #"{"removed":"d1"}"#), (200, door), (200, door), (200, door), (200, #"{"state":"done"}"#), (200, #"{"state":"done"}"#)])
        _ = try await client.addDoor("taf-1", app: "email")
        let closed = try await client.setDoorOpen("taf-1", door: "d1", open: false)
        try await client.removeDoor("taf-1", door: "d1")
        _ = try await client.pair("taf-1", door: "d1", sender: "ana@acme.example", name: "Ana")
        _ = try await client.pair("taf-1", door: "d1", sender: "bo@acme.example", name: "")
        _ = try await client.unpair("taf-1", door: "d1", sender: "ana@acme.example")
        try await client.answerKnock("taf-1", knock: "k1", action: "do", say: "Refund it")
        try await client.answerKnock("taf-1", knock: "k1", action: "ignore", say: "")
        try expectEqual(closed.open, false)
        try expectEqual(transport.sent.map { $0.method + " " + $0.path }, [
            "POST /v1/tafs/taf-1/doors", "PATCH /v1/tafs/taf-1/doors/d1", "DELETE /v1/tafs/taf-1/doors/d1",
            "POST /v1/tafs/taf-1/doors/d1/keys", "POST /v1/tafs/taf-1/doors/d1/keys",
            "DELETE /v1/tafs/taf-1/doors/d1/keys/ana%40acme%2Eexample",
            "POST /v1/tafs/taf-1/doors/knocks/k1", "POST /v1/tafs/taf-1/doors/knocks/k1",
        ])
        try expectEqual(try json(transport.sent[0].body), ["app": "email"])
        try expectEqual(try json(transport.sent[1].body), ["open": false])
        try expectEqual(transport.sent[2].body, Data())
        try expectEqual(try json(transport.sent[3].body), ["id": "ana@acme.example", "name": "Ana"])
        try expectEqual(try json(transport.sent[4].body), ["id": "bo@acme.example"])
        try expectEqual(try json(transport.sent[6].body), ["action": "do", "say": "Refund it"])
        try expectEqual(try json(transport.sent[7].body), ["action": "ignore"])
    }),
    Test("a refused change throws tafs cloud's refusal, and an answer without the door isn't one", awaiting: {
        let (client, _) = cloud([(429, #"{"error":"too_many"}"#), (200, "{}")])
        do { _ = try await client.setDoorOpen("taf-1", door: "d1", open: true); throw Failure(description: "taken") } catch let refusal as CloudRefusal {
            try expectEqual(refusal.status, 429)
        }
        do { _ = try await client.setDoorOpen("taf-1", door: "d1", open: true); throw Failure(description: "read") } catch let error as KIFFError {
            try expectEqual(error, .unreadable)
        }
    }),
    Test("Home's doors count the knocks Needs you shows; what doesn't read is nothing, a list that isn't one fails the taf") {
        let taf = { (doors: String) in #"{"kiff_agent":"a","name":"Refunds","state":"working"\#(doors)}"# }
        let page = try AccountClient.decoder.decode(Home.Page.self, from: Data(("{\"tafs\":[" + taf(#","doors":[{"app":"email","open":true,"knocks":2},{"knocks":"x"},{"app":"sms","knocks":1}]"#) + "," + taf("") + "],\"doors_offered\":[\"email\"]}").utf8))
        try expectEqual(TafDoors.knocks(page.tafs[0].doors), 3)
        try expectEqual(TafDoors.knocks(page.tafs[1].doors), 0)
        try expectEqual(page.doorsOffered, ["email"])
        let notAList = try? AccountClient.decoder.decode(Home.Page.self, from: Data(("{\"tafs\":[" + taf(#","doors":7"#) + "]}").utf8))
        try expect(notAList == nil, "doors that aren't a list")
        try expectEqual(TafDoors.label("whatsapp"), "WhatsApp")
        try expectEqual(TafDoors.label("sms"), "Sms")
        try expectEqual(TafDoors.mark("email"), "@")
        try expectEqual(TafDoors.mark("slack"), "S")
    },
]
