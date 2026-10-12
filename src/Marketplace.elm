module Marketplace exposing
    ( Category(..)
    , ContactInfo
    , Filter
    , Listing
    , ListingInput
    , Neighborhood(..)
    , Price
    , PublishedListing
    , SortOrder(..)
    , categories
    , categoryFromName
    , categoryName
    , contactText
    , createListing
    , expireListings
    , filterListings
    , freePrice
    , listingArtClass
    , listingCategory
    , listingContact
    , listingDescription
    , listingEmoji
    , listingExpiresAt
    , listingId
    , listingNeighborhood
    , listingOwner
    , listingPrice
    , listingTitle
    , neighborhoodFromName
    , neighborhoodName
    , neighborhoods
    , pageCount
    , paginate
    , priceFromCents
    , priceFromInput
    , priceLabel
    , publishListing
    , publishedListing
    , publishedListingDecoder
    , publishedListingEncoder
    , sampleListings
    , sortByPrice
    , weekInMilliseconds
    )

import Char
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import List
import String


type Category
    = Tools
    | Outdoors
    | Home
    | Electronics
    | Sports


type Neighborhood
    = Maplewood
    | Riverside
    | OakHill


type Price
    = Free
    | DailyPrice Int


type ContactInfo
    = ContactInfo String


freePrice : Price
freePrice =
    Free


type SortOrder
    = Recommended
    | PriceAscending


type Listing
    = Listing ListingFields


type alias ListingFields =
    { id : String
    , title : NonEmptyTitle
    , category : Category
    , neighborhood : Neighborhood
    , owner : String
    , price : Price
    , contact : ContactInfo
    , emoji : String
    , artClass : String
    , description : String
    }


type NonEmptyTitle
    = NonEmptyTitle String


type alias ListingInput =
    { id : String
    , title : String
    , category : Category
    , neighborhood : Neighborhood
    , owner : String
    , price : Price
    , contact : String
    , emoji : String
    , artClass : String
    , description : String
    }


type PublishedListing
    = PublishedListing Listing Int


type alias ListingWireBase =
    { id : String
    , title : String
    , category : String
    , neighborhood : String
    , owner : String
    , priceCents : Int
    , contact : String
    , emoji : String
    , artClass : String
    , description : String
    , expiresAt : Int
    }


weekInMilliseconds : Int
weekInMilliseconds =
    7 * 24 * 60 * 60 * 1000


type alias Filter =
    { query : String
    , category : Maybe Category
    , neighborhood : Maybe Neighborhood
    }


categories : List Category
categories =
    [ Tools, Outdoors, Home, Electronics, Sports ]


categoryName : Category -> String
categoryName category =
    case category of
        Tools ->
            "Tools"

        Outdoors ->
            "Outdoors"

        Home ->
            "Home"

        Electronics ->
            "Electronics"

        Sports ->
            "Sports"


categoryFromName : String -> Maybe Category
categoryFromName name =
    List.filter (\category -> categoryName category == name) categories
        |> List.head


neighborhoods : List Neighborhood
neighborhoods =
    [ Maplewood, Riverside, OakHill ]


neighborhoodName : Neighborhood -> String
neighborhoodName neighborhood =
    case neighborhood of
        Maplewood ->
            "Maplewood"

        Riverside ->
            "Riverside"

        OakHill ->
            "Oak Hill"


neighborhoodFromName : String -> Maybe Neighborhood
neighborhoodFromName name =
    List.filter (\neighborhood -> neighborhoodName neighborhood == name) neighborhoods
        |> List.head


createListing : ListingInput -> Result String Listing
createListing input =
    let
        title =
            String.trim input.title
    in
    if title == "" then
        Err "Add a name for your item before sharing it."

    else if String.trim input.id == "" then
        Err "A listing needs an ID."

    else if String.trim input.owner == "" then
        Err "A listing needs an owner."

    else if String.trim input.contact == "" then
        Err "Add at least one way for a neighbor to contact you."

    else if String.length (String.trim input.contact) > 500 then
        Err "Contact details must be 500 characters or fewer."

    else if String.length (String.trim input.title) > 120 then
        Err "Listing names must be 120 characters or fewer."

    else if String.length input.description > 2000 then
        Err "Listing details must be 2,000 characters or fewer."

    else
        Ok
            (Listing
                { id = String.trim input.id
                , title = NonEmptyTitle title
                , category = input.category
                , neighborhood = input.neighborhood
                , owner = String.trim input.owner
                , price = input.price
                , contact = ContactInfo (String.trim input.contact)
                , emoji = input.emoji
                , artClass = input.artClass
                , description = input.description
                }
            )


listingId : Listing -> String
listingId (Listing fields) =
    fields.id


listingTitle : Listing -> String
listingTitle (Listing fields) =
    case fields.title of
        NonEmptyTitle title ->
            title


listingCategory : Listing -> Category
listingCategory (Listing fields) =
    fields.category


listingContact : Listing -> ContactInfo
listingContact (Listing fields) =
    fields.contact


contactText : ContactInfo -> String
contactText (ContactInfo contact) =
    contact


listingNeighborhood : Listing -> Neighborhood
listingNeighborhood (Listing fields) =
    fields.neighborhood


listingOwner : Listing -> String
listingOwner (Listing fields) =
    fields.owner


listingPrice : Listing -> Price
listingPrice (Listing fields) =
    fields.price


listingEmoji : Listing -> String
listingEmoji (Listing fields) =
    fields.emoji


listingArtClass : Listing -> String
listingArtClass (Listing fields) =
    fields.artClass


listingDescription : Listing -> String
listingDescription (Listing fields) =
    fields.description


priceFromCents : Int -> Result String Price
priceFromCents cents =
    if cents < 0 then
        Err "Price cannot be negative."

    else if cents > 10000000 then
        Err "Daily price must be between $0 and $100,000."

    else if cents == 0 then
        Ok Free

    else
        Ok (DailyPrice cents)


priceFromInput : String -> Result String Price
priceFromInput input =
    let
        validDigits value =
            String.all Char.isDigit value

        dollarsToPrice dollars fraction =
            if dollars < 0 || dollars > 100000 then
                Err "Daily price must be between $0 and $100,000."

            else
                let
                    cents =
                        dollars * 100 + fraction
                in
                if cents == 0 then
                    Ok Free

                else if cents > 10000000 then
                    Err "Daily price must be between $0 and $100,000."

                else
                    Ok (DailyPrice cents)

        parseParts dollarsText fractionText =
            let
                normalizedDollars =
                    if dollarsText == "" then
                        "0"

                    else
                        dollarsText

                fraction =
                    if fractionText == "" then
                        "0"

                    else
                        fractionText
                            |> String.padRight 2 '0'
                            |> String.left 2
            in
            if not (validDigits normalizedDollars) then
                Err "Enter a valid daily price."

            else if not (validDigits fractionText) || String.length fractionText > 2 then
                Err "Enter a valid price with no more than two decimal places."

            else
                case ( String.toInt normalizedDollars, String.toInt fraction ) of
                    ( Just dollars, Just cents ) ->
                        dollarsToPrice dollars cents

                    _ ->
                        Err "Enter a valid daily price."
    in
    if String.trim input == "" then
        Err "Enter a valid daily price."

    else
        case String.split "." (String.trim input) of
            [ dollars ] ->
                parseParts dollars ""

            [ dollars, fraction ] ->
                parseParts dollars fraction

            _ ->
                Err "Enter a valid price with no more than two decimal places."


priceLabel : Price -> String
priceLabel price =
    case price of
        Free ->
            "Free"

        DailyPrice cents ->
            if modBy 100 cents == 0 then
                "$" ++ String.fromInt (cents // 100) ++ " / day"

            else
                "$"
                    ++ String.fromInt (cents // 100)
                    ++ "."
                    ++ String.padLeft 2 '0' (String.fromInt (modBy 100 cents))
                    ++ " / day"


filterListings : Filter -> List Listing -> List Listing
filterListings filters listings =
    let
        normalizedQuery =
            String.toLower (String.trim filters.query)

        matches listing =
            let
                title =
                    listingTitle listing

                category =
                    listingCategory listing

                neighborhood =
                    listingNeighborhood listing

                owner =
                    listingOwner listing

                queryMatches =
                    normalizedQuery
                        == ""
                        || String.contains normalizedQuery (String.toLower title)
                        || String.contains normalizedQuery (String.toLower (categoryName category))
                        || String.contains normalizedQuery (String.toLower (neighborhoodName neighborhood))
                        || String.contains normalizedQuery (String.toLower owner)
            in
            queryMatches
                && (filters.category == Nothing || filters.category == Just category)
                && (filters.neighborhood == Nothing || filters.neighborhood == Just neighborhood)
    in
    List.filter matches listings


sortByPrice : List Listing -> List Listing
sortByPrice =
    List.sortBy
        (\listing ->
            case listingPrice listing of
                Free ->
                    0

                DailyPrice cents ->
                    cents
        )


pageCount : Int -> Int -> Int
pageCount size total =
    if size <= 0 then
        1

    else
        max 1 ((total + size - 1) // size)


paginate : Int -> Int -> List a -> List a
paginate page size items =
    if size <= 0 then
        []

    else
        items
            |> List.drop (max 0 (page - 1) * size)
            |> List.take size


sampleListings : List Listing
sampleListings =
    [ makeSampleListing "cordless-drill" "Cordless drill set" Tools Maplewood "Maya" Free "maya@example.test" "🛠️" "art-sand" "A handy 18V drill with two batteries and a full set of bits. Great for shelves, furniture, and weekend projects."
    , makeSampleListing "camping-tent" "Two-person camping tent" Outdoors Riverside "Jordan" (DailyPrice 1200) "jordan@example.test" "⛺" "art-green" "Lightweight, waterproof tent with a footprint and rain fly. Packs down small and is ready for your next trip."
    , makeSampleListing "standing-mixer" "Stand mixer" Home OakHill "Priya" (DailyPrice 800) "priya@example.test" "🥣" "art-pink" "A reliable mixer with whisk, paddle, and dough hook attachments. Happy to share recipe tips too."
    , makeSampleListing "projector" "Portable projector" Electronics Maplewood "Alex" (DailyPrice 1500) "alex@example.test" "📽️" "art-blue" "1080p portable projector with HDMI cable. Makes backyard movie nights easy."
    , makeSampleListing "basketball" "Outdoor basketball" Sports Riverside "Sam" Free "sam@example.test" "🏀" "art-orange" "A well-loved size 7 basketball. Borrow it for the afternoon and bring it back with a little air."
    , makeSampleListing "pressure-washer" "Electric pressure washer" Tools OakHill "Lee" (DailyPrice 2000) "lee@example.test" "🚿" "art-lilac" "Compact pressure washer with several spray tips. Perfect for patios, bikes, and garden furniture."
    , makeSampleListing "picnic-basket" "Picnic basket for four" Outdoors Maplewood "Nina" (DailyPrice 500) "nina@example.test" "🧺" "art-yellow" "A roomy woven basket with reusable plates, cups, and cutlery for four people."
    , makeSampleListing "sewing-machine" "Beginner sewing machine" Home Riverside "Chris" (DailyPrice 1000) "chris@example.test" "🧵" "art-mint" "Easy-to-use sewing machine with a few thread colors and a simple instruction booklet."
    , makeSampleListing "bike-pump" "Floor bike pump" Sports OakHill "Taylor" Free "taylor@example.test" "🚲" "art-blue" "A sturdy floor pump with a pressure gauge and adapters for common bike valves."
    ]


publishListing : Int -> Listing -> PublishedListing
publishListing createdAt listing =
    PublishedListing listing (createdAt + weekInMilliseconds)


publishedListing : PublishedListing -> Listing
publishedListing (PublishedListing listing _) =
    listing


listingExpiresAt : PublishedListing -> Int
listingExpiresAt (PublishedListing _ expiresAt) =
    expiresAt


expireListings : Int -> List PublishedListing -> List PublishedListing
expireListings now =
    List.filter (\published -> now < listingExpiresAt published)


publishedListingEncoder : PublishedListing -> Encode.Value
publishedListingEncoder (PublishedListing (Listing fields) expiresAt) =
    Encode.object
        [ ( "id", Encode.string fields.id )
        , ( "title", Encode.string (listingTitle (Listing fields)) )
        , ( "category", Encode.string (categoryName fields.category) )
        , ( "neighborhood", Encode.string (neighborhoodName fields.neighborhood) )
        , ( "owner", Encode.string fields.owner )
        , ( "priceCents", Encode.int (priceCents fields.price) )
        , ( "contact", Encode.string (contactText fields.contact) )
        , ( "emoji", Encode.string fields.emoji )
        , ( "artClass", Encode.string fields.artClass )
        , ( "description", Encode.string fields.description )
        , ( "expiresAt", Encode.int expiresAt )
        ]


publishedListingDecoder : Decoder PublishedListing
publishedListingDecoder =
    Decode.andThen
        (\wire ->
            case ( categoryFromName wire.category, neighborhoodFromName wire.neighborhood, priceFromCents wire.priceCents ) of
                ( Just category, Just neighborhood, Ok price ) ->
                    case
                        createListing
                            { id = wire.id
                            , title = wire.title
                            , category = category
                            , neighborhood = neighborhood
                            , owner = wire.owner
                            , price = price
                            , contact = wire.contact
                            , emoji = wire.emoji
                            , artClass = wire.artClass
                            , description = wire.description
                            }
                    of
                        Ok listing ->
                            Decode.succeed (PublishedListing listing wire.expiresAt)

                        Err message ->
                            Decode.fail message

                _ ->
                    Decode.fail "Stored listing has an invalid category, neighborhood, or price."
        )
        (Decode.map8
            (\id title category neighborhood owner cents contact emoji ->
                { id = id
                , title = title
                , category = category
                , neighborhood = neighborhood
                , owner = owner
                , priceCents = cents
                , contact = contact
                , emoji = emoji
                , artClass = ""
                , description = ""
                , expiresAt = 0
                }
            )
            (Decode.field "id" Decode.string)
            (Decode.field "title" Decode.string)
            (Decode.field "category" Decode.string)
            (Decode.field "neighborhood" Decode.string)
            (Decode.field "owner" Decode.string)
            (Decode.field "priceCents" Decode.int)
            (Decode.field "contact" Decode.string)
            (Decode.field "emoji" Decode.string)
            |> Decode.andThen
                (\partial ->
                    Decode.map3
                        (\artClass description expiresAt ->
                            { partial
                                | artClass = artClass
                                , description = description
                                , expiresAt = expiresAt
                            }
                        )
                        (Decode.field "artClass" Decode.string)
                        (Decode.field "description" Decode.string)
                        (Decode.field "expiresAt" Decode.int)
                )
        )


priceCents : Price -> Int
priceCents price =
    case price of
        Free ->
            0

        DailyPrice cents ->
            cents


makeSampleListing : String -> String -> Category -> Neighborhood -> String -> Price -> String -> String -> String -> String -> Listing
makeSampleListing id title category neighborhood owner price contact emoji artClass description =
    Listing
        { id = id
        , title = NonEmptyTitle title
        , category = category
        , neighborhood = neighborhood
        , owner = owner
        , price = price
        , contact = ContactInfo contact
        , emoji = emoji
        , artClass = artClass
        , description = description
        }
