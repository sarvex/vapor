import Async
import TLS
import JunkDrawer
import Dispatch
import Fluent
import FluentSQLite
import Foundation
import HTTP
import Leaf
import Routing
import Service
import SQLite
import Vapor

let beta = DatabaseIdentifier<SQLiteDatabase>("beta")
let alpha = DatabaseIdentifier<SQLiteDatabase>("alpha")

print(AutoUser.properties())

extension Request: DatabaseConnectable {}

do {
    var services = Services.default()
    services.instance(SQLiteStorage.file(path: "/tmp/alpha.sqlite"))
    try services.provider(LeafProvider())
    try services.provider(FluentProvider())
    try services.provider(SQLiteProvider())

//    var engineConfig = EngineServerConfig()
//    engineConfig.ssl = EngineServerSSLConfig(settings:
//        SSLServerSettings(
//            hostname: "localhost",
//            publicKey: "/Users/joannisorlandos/Documents/vapor/vapor/Tests/TLSTests/public.pem",
//            privateKey: "/Users/joannisorlandos/Documents/vapor/vapor/Tests/TLSTests/private.pem"
//        )
//    )
//
//    engineConfig.ssl?.port = 8081
//    services.register(engineConfig)

    var databaseConfig = DatabaseConfig()
    databaseConfig.add(database: SQLiteDatabase.self, as: alpha)
    databaseConfig.add(
        database: SQLiteDatabase(storage: .file(path: "/tmp/beta.sqlite")),
        as: beta
    )
    databaseConfig.enableLogging(on: beta)
    services.instance(databaseConfig)


    var migrationConfig = MigrationConfig()
    migrationConfig.add(model: User.self, database: beta)
    migrationConfig.add(migration: AddUsers.self, database: beta)
    migrationConfig.add(model: Pet.self, database: beta)
    migrationConfig.add(model: Toy.self, database: beta)
    migrationConfig.add(model: PetToyPivot.self, database: beta)
    migrationConfig.add(migration: TestSiblings.self, database: beta)
    migrationConfig.add(model: AutoUser.self, database: .beta)
    services.instance(migrationConfig)

    let middlewareConfig = MiddlewareConfig()
    //middlewareConfig.use(ErrorMiddleware.self)
    services.instance(middlewareConfig)

    
    let dir = DirectoryConfig(workDir: "/Users/tanner/dev/vapor/vapor/Sources/Development/")
    services.instance(dir)

    let app = try Application(services: services)

    let router = try app.make(Router.self)

    router.get("example") { req -> Future<Response> in
        let client = try req.make(Client.self, for: Request.self)
        
        return client.send(.get, to: "http://www.zombo.com/")
    }
    
    router.get("example1") { req -> Future<Response> in
        let client = try req.make(Client.self, for: Request.self)
        
        return client.send(.get, to: "http://www.romansgohome.com")
    }
    
    router.get("example2") { req -> Future<Response> in
        let client = try req.make(Client.self, for: Request.self)
        
        return client.send(.get, to: "http://example.com")
    }
    
    router.get("example3") { req -> Future<Response> in
        let client = try req.make(Client.self, for: Request.self)
        
        return client.send(.get, to: "https://www.google.com")
    }
    
    router.get("hello2") { req -> Future<[User]> in
        let user = User(name: "Vapor", age: 3);
        return Future([user])
    }

    struct LoginRequest: Content {
        var email: String
        var password: String
    }

    let helloRes = try! HTTPResponse(headers: [
        .contentType: "text/plain; charset=utf-8"
    ], body: "Hello, world!")
    router.get("plaintext") { req in
        return Future(helloRes)
    }

    router.post("login") { req -> Future<Response> in
        let loginRequest = try req.content.decode(LoginRequest.self)

        print(loginRequest.email) // user@vapor.codes
        print(loginRequest.password) // don't look!

        return Future(req.makeResponse())
    }

    router.get("leaf") { req -> Future<View> in
//        let promise = Promise(User.self)
        // user.futureChild = promise.future
//        req.eventLoop.asyncAfter(deadline: .now() + 2) {
//            let user = User(name: "unborn", age: -1)
//            promise.complete(user)
//        }

        let user = User(name: "Vapor", age: 3);
        return try req.make(ViewRenderer.self).make("/Users/tanner/Desktop/hello", user)
    }

    final class FooController {
        func foo(_ req: Request) -> Future<Response> {
            return req.withConnection(to: alpha) { db in
                return Future(req.makeResponse())
            }
        }
    }

    let controller = FooController()
    router.post("login", use: controller.foo)

    final class Message: Model {
        typealias Database = SQLiteDatabase
        static let idKey = \Message.id

        var id: String?
        var text: String
        var time: Int

        init(id: String? = nil, text: String, time: Int) {
            self.id = id
            self.text = text
            self.time = time
        }

        init(from decoder: Decoder) throws {
            let container = try Message.decodingContainer(for: decoder)
            id = try container.decode(key: \Message.id)
            text = try container.decode(key: \Message.text)
            time = try container.decode(key: \Message.time)
        }

        func encode(to encoder: Encoder) throws {
            var container = encodingContainer(for: encoder)
            try container.encode(key: \Message.id)
            try container.encode(key: \Message.text)
            try container.encode(key: \Message.time)
        }
    }

    router.get("userview") { req -> Future<View> in
        let user = User.query(on: req).first()

        return try req.make(ViewRenderer.self).make("/Users/tanner/Desktop/hello", [
            "user": user
        ])
    }

    struct InvalidBody: Error{}

    router.post("users") { req -> Future<User> in
        guard let data = req.http.body.data else {
            throw InvalidBody()
        }

        let user = try JSONDecoder().decode(User.self, from: data)
        return user.save(on: req).map(to: User.self) { user }
    }

    router.get("builder") { req -> Future<[User]> in
        return try User.query(on: req).filter(\User.name == "Bob").all()
    }


    router.get("transaction") { req -> Future<String> in
        return req.withConnection(to: beta) { db in
            db.transaction { db in
                let user = User(name: "NO SAVE", age: 500)
                let message = Message(id: nil, text: "asdf", time: 42)

                return [
                    user.save(on: db),
                    message.save(on: db)
                ].flatten()
            }.map(to: String.self) {
                return "Done"
            }
        }
    }

    router.get("pets", Pet.parameter, "toys") { req in
        return try req.parameter(Pet.self).flatMap(to: [Toy].self) { pet in
            return try pet.toys.query(on: req).all()
        }
    }

    router.get("string", String.parameter) { req -> Future<String> in
        return try Future(req.parameter(String.self))
    }

    router.get("error") { req -> Future<String> in
        throw Abort(.internalServerError, reason: "Test error")
    }

    router.get("users") { req -> Future<Response> in
        let marie = User(name: "Marie Curie", age: 66)
        let charles = User(name: "Charles Darwin", age: 73)

        return [
            marie.save(on: req),
            charles.save(on: req)
        ].map(to: Response.self) {
            return req.makeResponse()
        }
    }

    router.get("fast") { req -> Future<Response> in
        let res = req.makeResponse()
        res.http.body = HTTPBody(string: "123")
        return Future(res)
    }

    router.get("123") { req -> Future<String> in
        return Future("123")
    }

    router.get("hello") { req in
        return try User.query(on: req).filter(\User.age > 50).all()
    }

    router.get("all") { req -> Future<String> in
        return try User.query(on: req).filter(\.name == "Vapor").all().map(to: String.self) { _ in
            return "done"
        }
    }
    
    router.websocket("foo") { (req, ws) in
        ws.onString { websocket, string in
            websocket.send(string: string)
        }
    }

    router.get("first") { req -> Future<User> in
        return try User.query(on: req).filter(\User.name == "Vapor").first().map(to: User.self) { user in
            guard let user = user else {
                throw Abort(.notFound)
            }
            return user
        }
    }

    router.get("asyncusers") { req -> Future<User> in
        let user = User(name: "Bob", age: 1)
        return user.save(on: req).map(to: User.self) {
            return user
        }
    }

    router.get("vapor") { req -> Future<String> in
        return try req.make(Client.self).send(.get, to: "https://vapor.codes").map(to: String.self) { res in
            print(res.http.headers)
            return "done!"
        }
    }
                                                                         
    router.get("query") { req -> Future<String> in
        struct Hello: Decodable {
            var name: String?
            var flag: Bool?
        }
        let hello = try req.query.decode(Hello.self)
        print(hello.flag ?? false)
        return Future(hello.name ?? "none")
    }

    router.get("redirect") { req in
        return Future(req.redirect(to: "http://google.com"))
    }

    router.get("leafcontext") { req -> Future<View> in
        let leaf = try req.make(LeafRenderer.self)
        return try leaf.make("home", [:] as [String: String])
    }

    //router.get("fuzzy") { req -> String in
    //    let data = req.content["foo", 1, "bar", "baz"]
    //    let flag = req.query["flag"]
    //    return data ?? flag ?? "none"
    //}

//    let foo = try app.withConnection(to: alpha) { alpha in
//        return try alpha.query(string: "select sqlite_version();").ex
//    }.blockingAwait()
//    print(foo)

    try app.run()
} catch {
    print("Top Level Error: \(error)")
    exit(1)
}

