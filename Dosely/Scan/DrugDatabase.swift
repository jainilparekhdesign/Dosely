import Foundation

struct DrugMatch: Equatable {
    enum Source: Equatable { case generic, indianBrand, rxNorm }
    /// Display name, corrected for OCR typos (e.g. "Amoxicilin" → "Amoxicillin").
    var name: String
    var generic: String
    var exact: Bool
    var source: Source
}

/// Offline drug-name matching. A compact bundled list covers the most common US generics and
/// Indian brands; RxNorm (RxNav) can optionally confirm anything else online.
enum DrugDatabase {
    static let generics: [String] = [
        "Acetaminophen", "Paracetamol", "Ibuprofen", "Naproxen", "Aspirin", "Diclofenac", "Aceclofenac", "Tramadol",
        "Amoxicillin", "Amoxicillin + Clavulanate", "Azithromycin", "Cefixime", "Cefuroxime", "Cefpodoxime", "Cephalexin",
        "Ciprofloxacin", "Levofloxacin", "Ofloxacin", "Doxycycline", "Metronidazole", "Nitrofurantoin", "Clindamycin",
        "Linezolid", "Fluconazole", "Acyclovir", "Valacyclovir", "Oseltamivir", "Ivermectin", "Albendazole",
        "Metformin", "Glimepiride", "Gliclazide", "Sitagliptin", "Vildagliptin", "Dapagliflozin", "Empagliflozin",
        "Pioglitazone", "Insulin Glargine", "Insulin Aspart", "Insulin Lispro",
        "Amlodipine", "Telmisartan", "Losartan", "Olmesartan", "Valsartan", "Lisinopril", "Enalapril", "Ramipril",
        "Metoprolol", "Atenolol", "Bisoprolol", "Carvedilol", "Propranolol", "Nebivolol", "Hydrochlorothiazide",
        "Chlorthalidone", "Furosemide", "Torsemide", "Spironolactone", "Clonidine",
        "Atorvastatin", "Rosuvastatin", "Simvastatin", "Pravastatin", "Ezetimibe", "Fenofibrate",
        "Clopidogrel", "Warfarin", "Apixaban", "Rivaroxaban", "Dabigatran",
        "Omeprazole", "Pantoprazole", "Esomeprazole", "Rabeprazole", "Lansoprazole", "Famotidine", "Ranitidine",
        "Domperidone", "Ondansetron", "Metoclopramide", "Loperamide", "Lactulose", "Bisacodyl",
        "Cetirizine", "Levocetirizine", "Loratadine", "Fexofenadine", "Montelukast", "Diphenhydramine",
        "Salbutamol", "Albuterol", "Budesonide", "Fluticasone", "Formoterol", "Tiotropium", "Ipratropium",
        "Prednisone", "Prednisolone", "Methylprednisolone", "Dexamethasone", "Hydrocortisone",
        "Levothyroxine", "Thyroxine", "Methimazole", "Carbimazole",
        "Sertraline", "Escitalopram", "Fluoxetine", "Paroxetine", "Citalopram", "Venlafaxine", "Duloxetine",
        "Bupropion", "Mirtazapine", "Trazodone", "Amitriptyline", "Alprazolam", "Clonazepam", "Lorazepam",
        "Zolpidem", "Quetiapine", "Olanzapine", "Risperidone", "Aripiprazole", "Lithium",
        "Gabapentin", "Pregabalin", "Levetiracetam", "Lamotrigine", "Valproate", "Sodium Valproate",
        "Carbamazepine", "Phenytoin", "Topiramate",
        "Tamsulosin", "Finasteride", "Sildenafil", "Tadalafil",
        "Allopurinol", "Febuxostat", "Colchicine", "Alendronate",
        "Folic Acid", "Vitamin D3", "Cholecalciferol", "Vitamin B12", "Methylcobalamin", "Calcium Carbonate",
        "Ferrous Sulfate", "Iron", "Multivitamin", "Zinc", "Potassium Chloride", "ORS",
        "Hydroxychloroquine", "Methotrexate", "Isotretinoin", "Mupirocin", "Clotrimazole",
        "Ketoconazole", "Betamethasone", "Hydroxyzine", "Ambroxol", "Dextromethorphan", "Guaifenesin",
        "Serratiopeptidase", "Rifaximin", "Ursodeoxycholic Acid", "Drotaverine", "Dicyclomine", "Mefenamic Acid",
        "Nimesulide", "Etoricoxib", "Thiocolchicoside", "Chlorzoxazone", "Ranolazine", "Isosorbide Mononitrate",
        "Nitroglycerin", "Digoxin", "Amiodarone", "Ivabradine", "Sacubitril + Valsartan", "Ticagrelor", "Prasugrel",
        "Linagliptin", "Teneligliptin", "Voglibose", "Acarbose", "Semaglutide", "Liraglutide", "Tirzepatide",
    ]

    /// Indian brand → generic composition (common brands; matching only).
    static let indianBrands: [String: String] = [
        "crocin": "Paracetamol", "dolo": "Paracetamol", "calpol": "Paracetamol", "pacimol": "Paracetamol",
        "combiflam": "Ibuprofen + Paracetamol", "brufen": "Ibuprofen", "zerodol": "Aceclofenac",
        "zerodol-p": "Aceclofenac + Paracetamol", "hifenac": "Aceclofenac", "voveran": "Diclofenac",
        "ultracet": "Tramadol + Paracetamol", "meftal": "Mefenamic Acid", "meftal-spas": "Mefenamic Acid + Dicyclomine",
        "augmentin": "Amoxicillin + Clavulanate", "clavam": "Amoxicillin + Clavulanate", "moxikind": "Amoxicillin + Clavulanate",
        "mox": "Amoxicillin", "novamox": "Amoxicillin", "azithral": "Azithromycin", "azee": "Azithromycin",
        "zithromax": "Azithromycin", "taxim": "Cefixime", "taxim-o": "Cefixime", "zifi": "Cefixime",
        "cifran": "Ciprofloxacin", "ciplox": "Ciprofloxacin", "oflox": "Ofloxacin", "zanocin": "Ofloxacin",
        "levoflox": "Levofloxacin", "metrogyl": "Metronidazole", "flagyl": "Metronidazole", "doxy-1": "Doxycycline",
        "glycomet": "Metformin", "glucophage": "Metformin", "gluconorm": "Metformin", "amaryl": "Glimepiride",
        "glimisave": "Glimepiride + Metformin", "janumet": "Sitagliptin + Metformin", "januvia": "Sitagliptin",
        "galvus": "Vildagliptin", "galvus met": "Vildagliptin + Metformin", "jardiance": "Empagliflozin",
        "forxiga": "Dapagliflozin", "istamet": "Sitagliptin + Metformin", "tenepride": "Teneligliptin",
        "lantus": "Insulin Glargine", "basalog": "Insulin Glargine", "novorapid": "Insulin Aspart",
        "telma": "Telmisartan", "telma-h": "Telmisartan + Hydrochlorothiazide", "telma-am": "Telmisartan + Amlodipine",
        "amlong": "Amlodipine", "amlokind": "Amlodipine", "stamlo": "Amlodipine", "losar": "Losartan",
        "repace": "Losartan", "olmezest": "Olmesartan", "met xl": "Metoprolol", "metolar": "Metoprolol",
        "concor": "Bisoprolol", "nebicard": "Nebivolol", "ciplar": "Propranolol", "inderal": "Propranolol",
        "lasix": "Furosemide", "dytor": "Torsemide", "aldactone": "Spironolactone",
        "atorva": "Atorvastatin", "lipitor": "Atorvastatin", "storvas": "Atorvastatin", "rosuvas": "Rosuvastatin",
        "rozavel": "Rosuvastatin", "crestor": "Rosuvastatin", "ecosprin": "Aspirin", "ecosprin-av": "Aspirin + Atorvastatin",
        "clopilet": "Clopidogrel", "plavix": "Clopidogrel", "deplatt": "Clopidogrel", "brilinta": "Ticagrelor",
        "pan": "Pantoprazole", "pan-d": "Pantoprazole + Domperidone", "pantocid": "Pantoprazole", "pantop": "Pantoprazole",
        "omez": "Omeprazole", "omez-d": "Omeprazole + Domperidone", "razo": "Rabeprazole", "rablet": "Rabeprazole",
        "rantac": "Ranitidine", "aciloc": "Ranitidine", "nexpro": "Esomeprazole", "sompraz": "Esomeprazole",
        "domstal": "Domperidone", "emeset": "Ondansetron", "ondem": "Ondansetron", "vomikind": "Ondansetron",
        "cyclopam": "Dicyclomine", "drotin": "Drotaverine", "duphalac": "Lactulose", "cremaffin": "Liquid Paraffin",
        "sporlac": "Lactobacillus", "econorm": "Saccharomyces", "electral": "ORS", "udiliv": "Ursodeoxycholic Acid",
        "cetzine": "Cetirizine", "okacet": "Cetirizine", "alerid": "Cetirizine", "levocet": "Levocetirizine",
        "teczine": "Levocetirizine", "allegra": "Fexofenadine", "montair": "Montelukast", "montair-lc": "Montelukast + Levocetirizine",
        "montek-lc": "Montelukast + Levocetirizine", "asthalin": "Salbutamol", "levolin": "Levosalbutamol",
        "budecort": "Budesonide", "foracort": "Formoterol + Budesonide", "seroflo": "Salmeterol + Fluticasone",
        "duolin": "Levosalbutamol + Ipratropium", "tiova": "Tiotropium", "deriphyllin": "Etofylline + Theophylline",
        "ascoril": "Ambroxol + Guaifenesin + Terbutaline", "benadryl": "Diphenhydramine", "grilinctus": "Dextromethorphan + Chlorpheniramine",
        "wysolone": "Prednisolone", "omnacortil": "Prednisolone", "medrol": "Methylprednisolone", "dexona": "Dexamethasone",
        "thyronorm": "Levothyroxine", "eltroxin": "Levothyroxine", "thyrox": "Levothyroxine", "neomercazole": "Carbimazole",
        "nexito": "Escitalopram", "stalopam": "Escitalopram", "fludac": "Fluoxetine", "serta": "Sertraline",
        "daxid": "Sertraline", "restyl": "Alprazolam", "alprax": "Alprazolam", "clonotril": "Clonazepam",
        "rivotril": "Clonazepam", "ativan": "Lorazepam", "nindral": "Zolpidem", "qutipin": "Quetiapine",
        "gabapin": "Gabapentin", "pregabid": "Pregabalin", "lyrica": "Pregabalin", "levipil": "Levetiracetam",
        "keppra": "Levetiracetam", "lamitor": "Lamotrigine", "valprol": "Sodium Valproate", "encorate": "Sodium Valproate",
        "tegretol": "Carbamazepine", "eptoin": "Phenytoin", "urimax": "Tamsulosin", "zyloric": "Allopurinol",
        "febustat": "Febuxostat", "shelcal": "Calcium + Vitamin D3", "calcimax": "Calcium + Vitamin D3",
        "uprise-d3": "Cholecalciferol", "calcirol": "Cholecalciferol", "d-rise": "Cholecalciferol",
        "neurobion": "Vitamin B Complex", "neurobion forte": "Vitamin B Complex", "nurokind": "Methylcobalamin",
        "methycobal": "Methylcobalamin", "becosules": "Vitamin B Complex + Vitamin C", "supradyn": "Multivitamin",
        "zincovit": "Multivitamin + Zinc", "limcee": "Vitamin C", "folvite": "Folic Acid", "livogen": "Ferrous Fumarate + Folic Acid",
        "autrin": "Iron + Folic Acid", "orofer": "Iron", "hcqs": "Hydroxychloroquine", "folitrax": "Methotrexate",
        "t-bact": "Mupirocin", "candid": "Clotrimazole", "betnovate": "Betamethasone", "atarax": "Hydroxyzine",
        "mucinac": "Acetylcysteine", "sinarest": "Paracetamol + Phenylephrine + Chlorpheniramine",
        "vicks action 500": "Paracetamol + Phenylephrine + Caffeine", "nise": "Nimesulide", "etoshine": "Etoricoxib",
        "myoril": "Thiocolchicoside", "chymoral forte": "Trypsin + Chymotrypsin", "rifagut": "Rifaximin",
        "sorbitrate": "Isosorbide Dinitrate", "monotrate": "Isosorbide Mononitrate", "ranolaz": "Ranolazine",
        "vymada": "Sacubitril + Valsartan", "xarelto": "Rivaroxaban", "eliquis": "Apixaban", "acitrom": "Acenocoumarol",
    ]

    private static let genericIndex: [String: String] = Dictionary(
        generics.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

    /// Match a name read from a prescription. Tries the whole name, then progressively shorter prefixes,
    /// then a typo-tolerant pass.
    static func match(_ raw: String) -> DrugMatch? {
        let cleaned = raw.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\-\+ ]"#, with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
        guard cleaned.count >= 3 else { return nil }
        let words = cleaned.split(separator: " ").map(String.init)

        for n in stride(from: min(words.count, 3), through: 1, by: -1) {
            let candidate = words.prefix(n).joined(separator: " ")
            if let brand = indianBrands[candidate] {
                return DrugMatch(name: titled(candidate), generic: brand, exact: true, source: .indianBrand)
            }
            if let generic = genericIndex[candidate] {
                return DrugMatch(name: generic, generic: generic, exact: true, source: .generic)
            }
        }

        // Typo-tolerant: OCR commonly drops or swaps a letter.
        guard let first = words.first, first.count >= 5 else { return nil }
        let maxDistance = first.count >= 8 ? 2 : 1
        var best: (String, String, DrugMatch.Source, Int)?
        for (key, generic) in genericIndex where !key.contains(" ") && abs(key.count - first.count) <= maxDistance {
            let d = levenshtein(first, key)
            if d <= maxDistance, d < (best?.3 ?? .max) { best = (generic, generic, .generic, d) }
        }
        for (key, generic) in indianBrands where key.count >= 5 && abs(key.count - first.count) <= maxDistance {
            let d = levenshtein(first, key)
            if d <= maxDistance, d < (best?.3 ?? .max) { best = (titled(key), generic, .indianBrand, d) }
        }
        guard let best else { return nil }
        return DrugMatch(name: best.0, generic: best.1, exact: false, source: best.2)
    }

    static func titled(_ s: String) -> String {
        s.split(separator: " ").map { word in
            word.split(separator: "-", omittingEmptySubsequences: false).map { part in
                part.count <= 2 ? part.uppercased() : part.prefix(1).uppercased() + part.dropFirst()
            }.joined(separator: "-")
        }.joined(separator: " ")
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}

/// Optional online confirmation against RxNorm via the NLM RxNav API (US names).
/// Only the medicine name is sent — never the prescription image. Off unless the user opts in.
enum RxNormClient {
    struct Response: Decodable {
        struct Group: Decodable { let candidate: [Candidate]? }
        struct Candidate: Decodable { let rxcui: String?; let name: String?; let score: String? }
        let approximateGroup: Group?
    }

    static func lookup(_ name: String) async -> DrugMatch? {
        var components = URLComponents(string: "https://rxnav.nlm.nih.gov/REST/approximateTerm.json")
        components?.queryItems = [
            URLQueryItem(name: "term", value: name),
            URLQueryItem(name: "maxEntries", value: "1"),
            URLQueryItem(name: "option", value: "1"),
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let candidate = decoded.approximateGroup?.candidate?.first,
              let rxName = candidate.name else { return nil }
        // RxNorm names look like "amoxicillin 500 MG Oral Capsule"; keep the ingredient part.
        let ingredient = rxName.split(separator: " ").prefix { !$0.first!.isNumber }.joined(separator: " ")
        guard !ingredient.isEmpty else { return nil }
        let display = ingredient.prefix(1).uppercased() + ingredient.dropFirst()
        let close = DrugDatabase.levenshtein(name.lowercased(), ingredient.lowercased()) <= 2
        return DrugMatch(name: close ? display : name, generic: display, exact: close, source: .rxNorm)
    }
}
