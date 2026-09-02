import Foundation
import CodexUsageCore

final class LiveResultBox {
    var result: Result<UsageSnapshot, Error>?
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

do {
    expect(CodexUsageLanguage.preferred(from: ["sv-SE"]) == .swedish, "Swedish was not selected for sv-SE")
    expect(CodexUsageLanguage.preferred(from: ["sv_SE"]) == .swedish, "Swedish was not selected for sv_SE")
    expect(CodexUsageLanguage.preferred(from: ["en-SE"]) == .english, "English was not selected for en-SE")
    expect(CodexUsageLanguage.preferred(from: ["de-DE"]) == .english, "English was not used as the fallback")
    expect(CodexUsageLanguage.preferred(from: []) == .english, "English was not used for an empty preference list")

    do {
        let response = """
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": {"usedPercent": 99, "windowDurationMins": 300}
            },
            "rateLimitsByLimitId": {
              "codex": {
                "planType": "plus",
                "primary": {
                  "usedPercent": 42,
                  "windowDurationMins": 10080,
                  "resetsAt": 1800000000
                }
              }
            }
          }
        }
        """

        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try UsageResponseParser.parse(Data(response.utf8), fetchedAt: fetchedAt)

        expect(snapshot.usedPercent == 42, "Fel använd procent")
        expect(snapshot.remainingPercent == 58, "Fel återstående procent")
        expect(snapshot.windowDurationMinutes == 10_080, "Fel fönsterlängd")
        expect(snapshot.resetsAt == Date(timeIntervalSince1970: 1_800_000_000), "Fel återställningstid")
        expect(snapshot.planType == "plus", "Fel abonnemangstyp")
        expect(snapshot.fetchedAt == fetchedAt, "Fel hämtningstid")
    }

    do {
        let response = """
        {
          "id": 2,
          "result": {
            "rateLimits": {
              "primary": {"usedPercent": 10, "windowDurationMins": 300},
              "secondary": {"usedPercent": 70, "windowDurationMins": 10080}
            }
          }
        }
        """

        let snapshot = try UsageResponseParser.parse(Data(response.utf8))

        expect(snapshot.usedPercent == 70, "Valde inte det längre veckofönstret")
        expect(snapshot.remainingPercent == 30, "Fel återstående procent för sekundärt fönster")
        expect(snapshot.windowDurationMinutes == 10_080, "Fel sekundär fönsterlängd")
    }

    do {
        let response = """
        {"id": 2, "result": {"rateLimits": {"planType": "plus"}}}
        """

        do {
            _ = try UsageResponseParser.parse(Data(response.utf8))
            fatalError("Ett svar utan gränsfönster skulle ha avvisats")
        } catch {
            // Förväntat.
        }
    }

    print("Alla parserkontroller godkändes.")
} catch {
    fatalError("Parserkontrollen misslyckades: \(error.localizedDescription)")
}

if CommandLine.arguments.contains("--live") {
    let semaphore = DispatchSemaphore(value: 0)
    let box = LiveResultBox()

    Task {
        do {
            box.result = .success(try await CodexUsageClient().fetch())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }

    semaphore.wait()

    switch box.result {
    case .success(let snapshot):
        print("Livekontroll godkänd: \(snapshot.remainingPercent)% kvar.")
    case .failure(let error):
        fatalError("Livekontrollen misslyckades: \(error.localizedDescription)")
    case .none:
        fatalError("Livekontrollen gav inget resultat.")
    }
}
