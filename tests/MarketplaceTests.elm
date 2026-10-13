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
                    Marketplace.filterListings
                        { query = "MAPLEWOOD"
                        , category = Nothing
                        , neighborhood = Nothing
                        }
                        Marketplace.sampleListings
                        |> List.map Marketplace.listingId
                        |> Expect.equal [ "cordless-drill", "projector", "picnic-basket" ]
            , test "category and neighborhood filters combine" <|
                \_ ->
                    Marketplace.filterListings
                        { query = ""
                        , category = Just Marketplace.Outdoors
                        , neighborhood = Just Marketplace.Riverside
                        }
                        Marketplace.sampleListings
                        |> List.map Marketplace.listingId
                        |> Expect.equal [ "camping-tent" ]
            , test "an unknown category cannot be parsed into the domain type" <|
                \_ ->
                    Marketplace.categoryFromName "Garden"
                        |> Expect.equal Nothing
            , test "an unknown neighborhood cannot be parsed into the domain type" <|
                \_ ->
                    Marketplace.neighborhoodFromName "Somewhere"
                        |> Expect.equal Nothing
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
                    Marketplace.sortByPrice Marketplace.sampleListings
                        |> List.take 3
                        |> List.map (Marketplace.listingPrice >> Marketplace.priceLabel)
                        |> Expect.equal [ "Free", "Free", "Free" ]
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
                        , neighborhood = Marketplace.Maplewood
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
                        , neighborhood = Marketplace.Maplewood
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
                        , neighborhood = Marketplace.Maplewood
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
                    Marketplace.sampleListings
                        |> List.take 1
                        |> List.map
                            (\listing ->
                                let
                                    published =
                                        Marketplace.publishListing 1000 listing
                                in
                                ( List.length (Marketplace.expireListings (1000 + Marketplace.weekInMilliseconds - 1) [ published ])
                                , List.length (Marketplace.expireListings (1000 + Marketplace.weekInMilliseconds) [ published ])
                                , Marketplace.listingExpiresAt published
                                )
                            )
                        |> Expect.equal [ ( 1, 0, 1000 + Marketplace.weekInMilliseconds ) ]
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
                    Marketplace.sampleListings
                        |> List.map roundTrip
                        |> Expect.equal
                            (List.map
                                (\listing ->
                                    Ok
                                        ( Marketplace.listingId listing
                                        , Marketplace.contactText (Marketplace.listingContact listing)
                                        , 1000 + Marketplace.weekInMilliseconds
                                        )
                                )
                                Marketplace.sampleListings
                            )
            , test "decodes rows returned by the ORDS collection endpoint" <|
                \_ ->
                    Decode.decodeString
                        (Decode.field "items" (Decode.list Marketplace.publishedListingDecoder))
                        """{"items":[{"listing_id":"a1b2c3","title":"Hand saw","category":"Tools","neighborhood":"Maplewood","owner_name":"A neighbor","price_cents":250,"contact":"Signal: @neighbor","emoji":"🪚","art_class":"art-mint","description":"Sharp and ready","expires_at_ms":1792000000000}],"hasMore":false}"""
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
