import Foundation

func localizedSiteURL(_ base: URL) -> URL {
    guard let language = Bundle.main.preferredLocalizations.first else { return base }
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
    var queryItems = components?.queryItems ?? []
    queryItems.append(URLQueryItem(name: "lang", value: language))
    components?.queryItems = queryItems
    return components?.url ?? base
}
