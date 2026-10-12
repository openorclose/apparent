module Api exposing (routes)

import ApiRoute exposing (ApiRoute)
import BackendTask exposing (BackendTask)
import BackendTask.Custom
import FatalError exposing (FatalError)
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Marketplace
import Pages.Manifest as Manifest
import Route exposing (Route)
import Server.Request
import Server.Response as Response
import Time


type alias StoredFile =
    { id : String
    , contents : String
    }


type alias ListingRequest =
    { title : String
    , category : String
    , neighborhood : String
    , price : String
    , contact : String
    , description : String
    }


routes :
    BackendTask FatalError (List Route)
    -> (Maybe { indent : Int, newLines : Bool } -> Html Never -> String)
    -> List (ApiRoute ApiRoute.Response)
routes getStaticRoutes htmlToString =
    [ ApiRoute.succeed listingsApi
        |> ApiRoute.literal "api"
        |> ApiRoute.slash
        |> ApiRoute.literal "listings"
        |> ApiRoute.serverRender
    ]


listingsApi : Server.Request.Request -> BackendTask FatalError (Response.Response Never Never)
listingsApi request =
    case Server.Request.method request of
        Server.Request.Get ->
            getListings request

        Server.Request.Post ->
            case Server.Request.jsonBody listingRequestDecoder request of
                Just (Ok listingRequest) ->
                    createListing request listingRequest

                Just (Err _) ->
                    errorResponse 400 "Invalid JSON or missing listing fields."

                Nothing ->
                    errorResponse 400 "Expected an application/json request body."

        _ ->
            errorResponse 405 "Only GET and POST are supported."
                |> BackendTask.map (Response.withHeader "Allow" "GET, POST")


getListings : Server.Request.Request -> BackendTask FatalError (Response.Response Never Never)
getListings request =
    BackendTask.Custom.run "readListingFiles" Encode.null (Decode.list storedFileDecoder)
        |> BackendTask.allowFatal
        |> BackendTask.andThen
            (\files ->
                case decodeStoredFiles files of
                    Err message ->
                        BackendTask.fail (FatalError.fromString ("Unable to read stored listing: " ++ message))

                    Ok listings ->
                        let
                            requestTime =
                                Time.posixToMillis (Server.Request.requestTime request)

                            expired =
                                List.filter
                                    (\published -> Marketplace.listingExpiresAt published <= requestTime)
                                    listings

                            active =
                                Marketplace.expireListings requestTime listings
                        in
                        if List.isEmpty expired then
                            activeListingsResponse active

                        else
                            BackendTask.Custom.run
                                "deleteListingFiles"
                                (Encode.list Encode.string (List.map (Marketplace.listingId << Marketplace.publishedListing) expired))
                                Decode.bool
                                |> BackendTask.allowFatal
                                |> BackendTask.andThen
                                    (\_ -> activeListingsResponse active)
            )


createListing : Server.Request.Request -> ListingRequest -> BackendTask FatalError (Response.Response Never Never)
createListing request raw =
    case validateListingRequest raw of
        Err message ->
            errorResponse 400 message

        Ok ( category, neighborhood, price ) ->
            BackendTask.Custom.run "newListingId" Encode.null Decode.string
                |> BackendTask.allowFatal
                |> BackendTask.andThen
                    (\id ->
                        case
                            Marketplace.createListing
                                { id = id
                                , title = raw.title
                                , category = category
                                , neighborhood = neighborhood
                                , owner = "A neighbor"
                                , price = price
                                , contact = raw.contact
                                , emoji = "📦"
                                , artClass = "art-mint"
                                , description = raw.description
                                }
                        of
                            Err message ->
                                errorResponse 400 message

                            Ok listing ->
                                let
                                    published =
                                        Marketplace.publishListing
                                            (Time.posixToMillis (Server.Request.requestTime request))
                                            listing

                                    contents =
                                        Marketplace.publishedListingEncoder published
                                            |> Encode.encode 2

                                    writeInput =
                                        Encode.object
                                            [ ( "id", Encode.string id )
                                            , ( "contents", Encode.string contents )
                                            ]
                                in
                                BackendTask.Custom.run "writeListingFile" writeInput Decode.bool
                                    |> BackendTask.allowFatal
                                    |> BackendTask.map
                                        (\_ ->
                                            Response.json (Marketplace.publishedListingEncoder published)
                                                |> Response.withStatusCode 201
                                                |> Response.withHeader "Cache-Control" "no-store"
                                        )
                    )


validateListingRequest : ListingRequest -> Result String ( Marketplace.Category, Marketplace.Neighborhood, Marketplace.Price )
validateListingRequest request =
    case ( Marketplace.categoryFromName request.category, Marketplace.neighborhoodFromName request.neighborhood, Marketplace.priceFromInput request.price ) of
        ( Just category, Just neighborhood, Ok price ) ->
            Ok ( category, neighborhood, price )

        ( Nothing, _, _ ) ->
            Err "Choose a valid listing category."

        ( _, Nothing, _ ) ->
            Err "Choose a valid neighborhood."

        ( _, _, Err message ) ->
            Err message


listingRequestDecoder : Decoder ListingRequest
listingRequestDecoder =
    Decode.map6 ListingRequest
        (Decode.field "title" Decode.string)
        (Decode.field "category" Decode.string)
        (Decode.field "neighborhood" Decode.string)
        (Decode.field "price" Decode.string)
        (Decode.field "contact" Decode.string)
        (Decode.field "description" Decode.string)


storedFileDecoder : Decoder StoredFile
storedFileDecoder =
    Decode.map2 StoredFile
        (Decode.field "id" Decode.string)
        (Decode.field "contents" Decode.string)


decodeStoredFiles : List StoredFile -> Result String (List Marketplace.PublishedListing)
decodeStoredFiles files =
    List.foldr
        (\file result ->
            case Decode.decodeString Marketplace.publishedListingDecoder file.contents of
                Err error ->
                    Err (Decode.errorToString error)

                Ok published ->
                    if Marketplace.listingId (Marketplace.publishedListing published) /= file.id then
                        Err "The listing ID does not match its text filename."

                    else
                        Result.map ((::) published) result
        )
        (Ok [])
        files


activeListingsResponse : List Marketplace.PublishedListing -> BackendTask FatalError (Response.Response Never Never)
activeListingsResponse listings =
    Encode.list Marketplace.publishedListingEncoder listings
        |> Response.json
        |> Response.withHeader "Cache-Control" "no-store"
        |> BackendTask.succeed


errorResponse : Int -> String -> BackendTask FatalError (Response.Response Never Never)
errorResponse status message =
    Encode.object [ ( "error", Encode.string message ) ]
        |> Response.json
        |> Response.withStatusCode status
        |> Response.withHeader "Cache-Control" "no-store"
        |> BackendTask.succeed


manifest : Manifest.Config
manifest =
    Manifest.init
        { name = "AppaRent"
        , description = "Share useful things with neighbors nearby."
        , startUrl = Route.Index |> Route.toPath
        , icons = []
        }
