import Foundation

struct BundledVocabulary {
    struct Pack: Sendable {
        let id: String
        let displayName: String
        let terms: [String]
        let corrections: [String: String]

        var termCount: Int { terms.count + corrections.count }
    }

    static let allPacks: [Pack] = [canadianPolitics, technology]

    static let canadianPolitics = Pack(
        id: "canadian-politics",
        displayName: "Canadian Politics",
        terms: [
            // Federal leaders
            "Mark Carney", "Pierre Poilievre", "Jagmeet Singh", "Yves-Francois Blanchet",
            // Premiers
            "David Eby", "Danielle Smith", "Doug Ford", "Francois Legault",
            "Tim Houston", "Wab Kinew", "Scott Moe", "Susan Holt",
            // Political figures
            "Tom Mulcair", "Vassy Kapelos", "Ken Bosenkool", "Thomas Lukaszuk",
            "Yan Fouche", "Chrystia Freeland", "Anita Anand",
            "Francois-Philippe Champagne", "Melanie Joly", "Marc Miller",
            "Steven MacKinnon", "Sean Fraser", "Michael Sabia",
            // BC politics
            "Adrian Dix", "Ravi Kahlon", "Bowinn Ma", "Niki Sharma",
            "Brenda Bailey", "John Rustad", "Sonia Furstenau",
            // Policy / advocacy
            "Erin Flanagan",
            // Federal departments / agencies
            "PMO", "PCO", "NRCan", "ECCC", "ESDC", "ISED", "IRCC", "GAC",
            "CRTC", "CRA", "CMHC", "DND", "CSIS", "RCMP", "CBSA",
            // Trade / agreements
            "PNWER", "CUSMA", "USMCA", "CPTPP", "DRIPA",
            // Proper nouns
            "Cowichan", "Delgamuukw", "PEAP", "Hansard",
            "Tahltan", "Gitxaala", "Barrick", "CFAA", "Landlord BC",
            // Organizations / firms
            "Crestview Strategy", "Hill+Knowlton",
            "Cadillac Fairview", "Strategy Corp", "Teneo",
            // Names that ASR gets close but not quite
            "Hoekstra", "Rexall", "Trudeau", "Kenney",
        ],
        corrections: [
            // Observed ASR errors from DRQS beta recordings
            "Mulker": "Mulcair",
            "Mulkare": "Mulcair",
            "Shudeau": "Trudeau",
            "Bozool": "Bosenkool",
            "Lukazak": "Lukaszuk",
            "Hookstra": "Hoekstra",
            "Penmar": "PNWER",
            "Penoir": "PNWER",
            "Kuzma": "CUSMA",
            "cousma": "CUSMA",
            "Helen Knowlton": "Hill+Knowlton",
            "Catalan Fairview": "Cadillac Fairview",
            "Taneo": "Teneo",
            "Strategy Core": "Strategy Corp",
            "woodpunk": "Woodfibre",
            "Anarchan": "NRCan",
            "Enercan": "NRCan",
            "Rexol": "Rexall",
            "LGBT Perch Fund": "LGBT Purge Fund",
            "brass tax": "brass tacks",
            "Mill Miller": "Marc Miller",
            "Vasi Kapalos": "Vassy Kapelos",
            // Recording 7 errors (Realstar pre-brief, 2026-05-26)
            "Couch and": "Cowichan",
            "Tol Tan": "Tahltan",
            "Tall Tan": "Tahltan",
            "Gataxla": "Gitxaala",
            "David E. V.": "David Eby",
            "Line Lord BC": "Landlord BC",
            "Line Lord": "Landlord",
            "CFFA": "CFAA",
            "Barrack Mining": "Barrick Mining",
        ]
    )

    static let technology = Pack(
        id: "technology",
        displayName: "Technology",
        terms: [
            // Companies
            "Anthropic", "OpenAI", "Shopify", "Wealthsimple", "Clio",
            "Hootsuite", "Lightspeed", "Cohere", "Databricks", "Palantir",
            "Stripe", "Twilio", "Datadog", "Snowflake", "MongoDB",
            "Cloudflare", "Figma", "Vercel", "Supabase", "Confluent",
            // Products / platforms
            "Kubernetes", "PostgreSQL", "Elasticsearch", "GraphQL",
            "Terraform", "Docker", "Redis", "Kafka", "NumPy", "PyTorch",
            "TensorFlow", "Hugging Face", "LangChain", "ChromaDB",
            // Acronyms
            "SaaS", "API", "LLM", "GenAI", "CUDA", "MLOps", "DevOps",
            "CI/CD", "gRPC", "OAuth", "OIDC", "RBAC", "SAML",
        ],
        corrections: [:]
    )
}
