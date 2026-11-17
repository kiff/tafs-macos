import Foundation

let recipeLogosTests: [Test] = [
    Test("a job's apps read their logo as the iPad's: only tafs cloud's own /v1/logos/ path, else the name alone") {
        let json = #"""
        {"categories":[{"id":"money","title":"Money"}],
         "recipes":[{"id":"r1","title":"Refunds","category":"money","line":"Refunds within its limit","say":"Refund orders",
                     "apps":[{"name":"Stripe","logo":"/v1/logos/0123456789abcdef0123456789abcdef"},{"name":"Gmail","logo":"https://cdn.example.com/gmail.png"},
                             {"name":"Qonto","logo":"/v1/logos/0123456789ABCDEF0123456789ABCDEF"},{"name":"Slack","logo":7},{"name":"Notion"},{"logo":"/v1/logos/0123456789abcdef0123456789abcdef"}]}]}
        """#
        let recipes = try JSONDecoder().decode(Recipes.self, from: Data(json.utf8))
        let apps = recipes.recipes[0].apps
        try expectEqual(apps.map(\.name), ["Stripe", "Gmail", "Qonto", "Slack", "Notion"])
        try expectEqual(apps.map(\.logo), ["/v1/logos/0123456789abcdef0123456789abcdef", nil, nil, nil, nil])
        try expectEqual(Recipes.App(name: "X", logo: "https://elsewhere/x.png").logo, nil)
    },
    Test("the gallery's jobs keep their apps' logos the same way") {
        let json = #"""
        {"categories":[{"id":"money","title":"Money"}],
         "recipes":[{"id":"r1","title":"Refunds","category":"money","line":"Refunds within its limit","say":"Refund orders",
                     "apps":[{"name":"Stripe","logo":"/v1/logos/ffffffffffffffffffffffffffffffff"},{"name":"Gmail","logo":"/v1/logos/../x"}]}],
         "words":{"title":"Start a new taf","all":"All jobs"}}
        """#
        let gallery = try JSONDecoder().decode(Gallery.self, from: Data(json.utf8))
        try expectEqual(gallery.asRecipes().recipes[0].apps.map(\.logo), ["/v1/logos/ffffffffffffffffffffffffffffffff", nil])
    },
]
