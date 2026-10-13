module MarketplaceTests exposing (tests)

import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Marketplace
import Test exposing (Test, describe, test)


tests : Test
tests =
    describe "Marketplace"
        [ describe "filterListings"
            [ test "search is case-insensitive and includes neighborhood names" <|
                \_ ->
                    expectFixtures
                        (\listings ->
                            Marketplace.filterListings
                                { query = "ANG MO KIO"
                                , category = Nothing
                                , neighborhood = Nothing
                                }
                                listings
                                |> List.map Marketplace.listingId
                                |> Expect.equal [ "ang-mo-kio-drill", "ang-mo-kio-projector", "ang-mo-kio-basket" ]
                        )
            , test "category and neighborhood filters combine" <|
                \_ ->
                    expectFixtures
                        (\listings ->
                            Marketplace.filterListings
                                { query = ""
                                , category = Just Marketplace.Outdoors
                                , neighborhood = Just Marketplace.Punggol
                                }
                                listings
                                |> List.map Marketplace.listingId
                                |> Expect.equal [ "punggol-tent" ]
                        )
            , test "an unknown category cannot be parsed into the domain type" <|
                \_ ->
                    Marketplace.categoryFromName "Garden"
                        |> Expect.equal Nothing
            , test "an unknown neighborhood cannot be parsed into the domain type" <|
                \_ ->
                    Marketplace.neighborhoodFromName "Somewhere"
                        |> Expect.equal Nothing
            , test "town choices are real Singapore towns and exclude old fictional options" <|
                \_ ->
                    ( List.map Marketplace.neighborhoodName Marketplace.neighborhoods
                    , [ Marketplace.neighborhoodFromName "Maplewood"
                      , Marketplace.neighborhoodFromName "Riverside"
                      , Marketplace.neighborhoodFromName "Oak Hill"
                      ]
                    )
                        |> Expect.equal
                            ( [ "Ang Mo Kio"
                              , "Bedok"
                              , "Bishan"
                              , "Bukit Batok"
                              , "Bukit Merah"
                              , "Bukit Panjang"
                              , "Choa Chu Kang"
                              , "Clementi"
                              , "Geylang"
                              , "Hougang"
                              , "Jurong East"
                              , "Jurong West"
                              , "Kallang/Whampoa"
                              , "Marine Parade"
                              , "Pasir Ris"
                              , "Punggol"
                              , "Queenstown"
                              , "Sembawang"
                              , "Sengkang"
                              , "Serangoon"
                              , "Tampines"
                              , "Toa Payoh"
                              , "Woodlands"
                              , "Yishun"
                              ]
                            , [ Nothing, Nothing, Nothing ]
                            )
            ]
        , describe "priceFromInput"
            [ test "parses free, whole-dollar, and fractional prices" <|
                \_ ->
                    [ "0", "12", "12.5", "12.50", "100000" ]
                        |> List.map (Marketplace.priceFromInput >> Result.map Marketplace.priceLabel)
                        |> Expect.equal
                            [ Ok "Free"
                            , Ok "$12 / day"
                            , Ok "$12.50 / day"
                            , Ok "$12.50 / day"
                            , Ok "$100000 / day"
                            ]
            , test "rejects negative, malformed, excessive-precision, and excessive prices" <|
                \_ ->
                    [ "", "-1", "one", "1.001", "100000.01" ]
                        |> List.map Marketplace.priceFromInput
                        |> Expect.equal
                            [ Err "Enter a valid daily price."
                            , Err "Enter a valid daily price."
                            , Err "Enter a valid daily price."
                            , Err "Enter a valid price with no more than two decimal places."
                            , Err "Daily price must be between $0 and $100,000."
                            ]
            ]
        , describe "sorting and pagination"
            [ test "sorts free items before paid items" <|
                \_ ->
                    expectFixtures
                        (\listings ->
                            Marketplace.sortByPrice listings
                                |> List.take 3
                                |> List.map (Marketplace.listingPrice >> Marketplace.priceLabel)
                                |> Expect.equal [ "Free", "Free", "$5 / day" ]
                        )
            , test "calculates at least one page for empty results" <|
                \_ ->
                    Marketplace.pageCount 6 0
                        |> Expect.equal 1
            , test "pagination clamps pages below the first page" <|
                \_ ->
                    Marketplace.paginate 0 2 [ "a", "b", "c" ]
                        |> Expect.equal [ "a", "b" ]
            ]
        , test "listing construction trims titles and rejects empty ones" <|
            \_ ->
                let
                    input title =
                        { id = " test-item "
                        , title = title
                        , category = Marketplace.Tools
                        , neighborhood = Marketplace.AngMoKio
                        , owner = " Test neighbor "
                        , price = Marketplace.freePrice
                        , contact = " maya@example.test "
                        , emoji = "🔧"
                        , artClass = "art-sand"
                        , description = ""
                        }
                in
                ( Marketplace.createListing (input "  Hand saw  ")
                    |> Result.map
                        (\listing ->
                            { title = Marketplace.listingTitle listing
                            , id = Marketplace.listingId listing
                            , owner = Marketplace.listingOwner listing
                            , contact = Marketplace.contactText (Marketplace.listingContact listing)
                            }
                        )
                , Marketplace.createListing (input "   ")
                )
                    |> Expect.equal
                        ( Ok
                            { title = "Hand saw"
                            , id = "test-item"
                            , owner = "Test neighbor"
                            , contact = "maya@example.test"
                            }
                        , Err "Add a name for your item before sharing it."
                        )
        , test "listing creation rejects missing identity fields" <|
            \_ ->
                let
                    base =
                        { id = "test-item"
                        , title = "A valid item"
                        , category = Marketplace.Tools
                        , neighborhood = Marketplace.AngMoKio
                        , owner = "Test neighbor"
                        , price = Marketplace.freePrice
                        , contact = "neighbor@example.test"
                        , emoji = "🔧"
                        , artClass = "art-sand"
                        , description = ""
                        }
                in
                ( Marketplace.createListing { base | id = " " }
                , Marketplace.createListing { base | owner = " " }
                )
                    |> Expect.equal
                        ( Err "A listing needs an ID."
                        , Err "A listing needs an owner."
                        )
        , test "listing creation requires contact information" <|
            \_ ->
                let
                    input =
                        { id = "test-item"
                        , title = "A valid item"
                        , category = Marketplace.Tools
                        , neighborhood = Marketplace.AngMoKio
                        , owner = "Test neighbor"
                        , price = Marketplace.freePrice
                        , contact = " "
                        , emoji = "🔧"
                        , artClass = "art-sand"
                        , description = ""
                        }
                in
                Marketplace.createListing input
                    |> Expect.equal (Err "Add at least one way for a neighbor to contact you.")
        , describe "seven-day expiry and persistence format"
            [ test "listings remain available until exactly seven days have elapsed" <|
                \_ ->
                    expectFixtures
                        (\listings ->
                            case List.head listings of
                                Just listing ->
                                    let
                                        published =
                                            Marketplace.publishListing 1000 listing
                                    in
                                    ( List.length (Marketplace.expireListings (1000 + Marketplace.weekInMilliseconds - 1) [ published ])
                                    , List.length (Marketplace.expireListings (1000 + Marketplace.weekInMilliseconds) [ published ])
                                    , Marketplace.listingExpiresAt published
                                    )
                                        |> Expect.equal ( 1, 0, 1000 + Marketplace.weekInMilliseconds )

                                Nothing ->
                                    Expect.fail "Test fixture listing was not created."
                        )
            , test "JSON storage round-trips each listing's contact and expiry" <|
                \_ ->
                    let
                        roundTrip listing =
                            let
                                published =
                                    Marketplace.publishListing 1000 listing

                                decoded =
                                    Marketplace.publishedListingEncoder published
                                        |> Encode.encode 0
                                        |> Decode.decodeString Marketplace.publishedListingDecoder
                            in
                            decoded
                                |> Result.map
                                    (\restored ->
                                        ( Marketplace.listingId (Marketplace.publishedListing restored)
                                        , Marketplace.contactText
                                            (Marketplace.listingContact (Marketplace.publishedListing restored))
                                        , Marketplace.listingExpiresAt restored
                                        )
                                    )
                                |> Result.mapError Decode.errorToString
                    in
                    expectFixtures
                        (\listings ->
                            List.map roundTrip listings
                                |> Expect.equal
                                    (List.map
                                        (\listing ->
                                            Ok
                                                ( Marketplace.listingId listing
                                                , Marketplace.contactText (Marketplace.listingContact listing)
                                                , 1000 + Marketplace.weekInMilliseconds
                                                )
                                        )
                                        listings
                                    )
                        )
            , test "decodes rows returned by the ORDS collection endpoint" <|
                \_ ->
                    Decode.decodeString
                        (Decode.field "items" (Decode.list Marketplace.publishedListingDecoder))
                        """{"items":[{"listing_id":"a1b2c3","title":"Hand saw","category":"Tools","neighborhood":"Bedok","owner_name":"A neighbor","price_cents":250,"contact":"Signal: @neighbor","emoji":"🪚","art_class":"art-mint","description":"Sharp and ready","expires_at_ms":1792000000000}],"hasMore":false}"""
                        |> Result.map
                            (List.map
                                (\published ->
                                    let
                                        listing =
                                            Marketplace.publishedListing published
                                    in
                                    { id = Marketplace.listingId listing
                                    , title = Marketplace.listingTitle listing
                                    , priceCents = Marketplace.priceInCents (Marketplace.listingPrice listing)
                                    , contact = Marketplace.contactText (Marketplace.listingContact listing)
                                    , expiresAt = Marketplace.listingExpiresAt published
                                    }
                                )
                            )
                        |> Expect.equal
                            (Ok
                                [ { id = "a1b2c3"
                                  , title = "Hand saw"
                                  , priceCents = 250
                                  , contact = "Signal: @neighbor"
                                  , expiresAt = 1792000000000
                                  }
                                ]
                            )
            ]
        ]


expectFixtures : (List Marketplace.Listing -> Expect.Expectation) -> Expect.Expectation
expectFixtures assertion =
    case fixtureListings of
        Ok listings ->
            assertion listings

        Err error ->
            Expect.fail error


fixtureListings : Result String (List Marketplace.Listing)
fixtureListings =
    Result.map3
        (\projectorPrice basketPrice tentPrice ->
            [ { id = "ang-mo-kio-drill"
              , title = "Cordless drill"
              , category = Marketplace.Tools
              , neighborhood = Marketplace.AngMoKio
              , owner = "Maya"
              , price = Marketplace.freePrice
              , contact = "maya@example.test"
              , emoji = "🛠️"
              , artClass = "art-sand"
              , description = "Test listing."
              }
            , { id = "ang-mo-kio-projector"
              , title = "Portable projector"
              , category = Marketplace.Electronics
              , neighborhood = Marketplace.AngMoKio
              , owner = "Alex"
              , price = projectorPrice
              , contact = "alex@example.test"
              , emoji = "📽️"
              , artClass = "art-blue"
              , description = "Test listing."
              }
            , { id = "ang-mo-kio-basket"
              , title = "Picnic basket"
              , category = Marketplace.Outdoors
              , neighborhood = Marketplace.AngMoKio
              , owner = "Nina"
              , price = basketPrice
              , contact = "nina@example.test"
              , emoji = "🧺"
              , artClass = "art-yellow"
              , description = "Test listing."
              }
            , { id = "punggol-tent"
              , title = "Camping tent"
              , category = Marketplace.Outdoors
              , neighborhood = Marketplace.Punggol
              , owner = "Jordan"
              , price = tentPrice
              , contact = "jordan@example.test"
              , emoji = "⛺"
              , artClass = "art-green"
              , description = "Test listing."
              }
            , { id = "bedok-basketball"
              , title = "Basketball"
              , category = Marketplace.Sports
              , neighborhood = Marketplace.Bedok
              , owner = "Sam"
              , price = Marketplace.freePrice
              , contact = "sam@example.test"
              , emoji = "🏀"
              , artClass = "art-orange"
              , description = "Test listing."
              }
            ]
        )
        (Marketplace.priceFromCents 1500)
        (Marketplace.priceFromCents 500)
        (Marketplace.priceFromCents 1200)
        |> Result.andThen
            (\inputs ->
                inputs
                    |> List.map Marketplace.createListing
                    |> List.foldr (Result.map2 (::)) (Ok [])
            )
