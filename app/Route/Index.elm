module Route.Index exposing (ActionData, Data, Model, Msg, route)

import BackendTask exposing (BackendTask)
import Effect exposing (Effect)
import FatalError exposing (FatalError)
import Head
import Html
import Html.Attributes as Attr
import Html.Events as Events
import Marketplace exposing (Listing)
import PagesMsg exposing (PagesMsg)
import RouteBuilder exposing (App, StatefulRoute)
import Shared
import String
import UrlPath exposing (UrlPath)
import View exposing (View)


type alias Model =
    { query : String
    , category : Maybe Marketplace.Category
    , neighborhood : Maybe Marketplace.Neighborhood
    , sortOrder : Marketplace.SortOrder
    , page : Int
    , addedListings : List Listing
    , dialog : Dialog
    , draft : ListingDraft
    , notice : Maybe String
    }


type Dialog
    = NoDialog
    | CreateListingDialog
    | ListingDetailsDialog String


type alias ListingDraft =
    { title : String
    , category : Marketplace.Category
    , neighborhood : Marketplace.Neighborhood
    , price : String
    , description : String
    }


type Msg
    = SearchChanged String
    | CategorySelected (Maybe Marketplace.Category)
    | NeighborhoodSelected String
    | SortByPrice
    | PageSelected Int
    | ShowCreateForm
    | HideCreateForm
    | TitleChanged String
    | CategoryDraftChanged String
    | NeighborhoodDraftChanged String
    | PriceChanged String
    | DescriptionChanged String
    | CreateListing
    | OpenListing String
    | CloseListing
    | ContactOwner
    | DismissNotice


type alias RouteParams =
    {}


type alias Data =
    { listings : List Listing
    }


type alias ActionData =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.single
        { head = head
        , data = data
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


data : BackendTask FatalError Data
data =
    BackendTask.succeed { listings = Marketplace.sampleListings }


init : App Data ActionData RouteParams -> Shared.Model -> ( Model, Effect Msg )
init app sharedModel =
    ( { query = ""
      , category = Nothing
      , neighborhood = Nothing
      , sortOrder = Marketplace.Recommended
      , page = 1
      , addedListings = []
      , dialog = NoDialog
      , draft =
            { title = ""
            , category = Marketplace.Tools
            , neighborhood = Marketplace.Maplewood
            , price = "0"
            , description = ""
            }
      , notice = Nothing
      }
    , Effect.none
    )


update :
    App Data ActionData RouteParams
    -> Shared.Model
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update app shared msg model =
    case msg of
        SearchChanged query ->
            ( { model | query = query, page = 1 }, Effect.none )

        CategorySelected category ->
            ( { model | category = category, page = 1 }, Effect.none )

        NeighborhoodSelected neighborhood ->
            case neighborhood of
                "" ->
                    ( { model | neighborhood = Nothing, page = 1 }, Effect.none )

                name ->
                    case Marketplace.neighborhoodFromName name of
                        Just value ->
                            ( { model | neighborhood = Just value, page = 1 }, Effect.none )

                        Nothing ->
                            ( model, Effect.none )

        SortByPrice ->
            ( { model
                | sortOrder =
                    case model.sortOrder of
                        Marketplace.Recommended ->
                            Marketplace.PriceAscending

                        Marketplace.PriceAscending ->
                            Marketplace.Recommended
                , page = 1
              }
            , Effect.none
            )

        PageSelected page ->
            ( { model | page = max 1 page }, Effect.none )

        ShowCreateForm ->
            ( { model | dialog = CreateListingDialog, notice = Nothing }, Effect.none )

        HideCreateForm ->
            ( { model | dialog = NoDialog }, Effect.none )

        TitleChanged title ->
            ( { model | draft = updateDraft model.draft (\draft -> { draft | title = title }) }, Effect.none )

        CategoryDraftChanged category ->
            case Marketplace.categoryFromName category of
                Just value ->
                    ( { model | draft = updateDraft model.draft (\draft -> { draft | category = value }) }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        NeighborhoodDraftChanged neighborhood ->
            case Marketplace.neighborhoodFromName neighborhood of
                Just value ->
                    ( { model | draft = updateDraft model.draft (\draft -> { draft | neighborhood = value }) }, Effect.none )

                Nothing ->
                    ( model, Effect.none )

        PriceChanged price ->
            ( { model | draft = updateDraft model.draft (\draft -> { draft | price = price }) }, Effect.none )

        DescriptionChanged description ->
            ( { model | draft = updateDraft model.draft (\draft -> { draft | description = description }) }, Effect.none )

        CreateListing ->
            createListing model

        OpenListing listingId ->
            ( { model | dialog = ListingDetailsDialog listingId, notice = Nothing }, Effect.none )

        CloseListing ->
            ( { model | dialog = NoDialog }, Effect.none )

        ContactOwner ->
            ( { model
                | dialog = NoDialog
                , notice = Just "Neighbor messaging is coming soon. No message has been sent."
              }
            , Effect.none
            )

        DismissNotice ->
            ( { model | notice = Nothing }, Effect.none )


updateDraft : ListingDraft -> (ListingDraft -> ListingDraft) -> ListingDraft
updateDraft draft transform =
    transform draft


createListing : Model -> ( Model, Effect Msg )
createListing model =
    let
        price =
            Marketplace.priceFromInput model.draft.price
    in
    case price of
        Err message ->
            ( { model | notice = Just message }, Effect.none )

        Ok validPrice ->
            let
                result =
                    Marketplace.createListing
                        { id = "shared-item-" ++ String.fromInt (List.length model.addedListings + 1)
                        , title = model.draft.title
                        , category = model.draft.category
                        , neighborhood = model.draft.neighborhood
                        , owner = "You"
                        , price = validPrice
                        , emoji = "📦"
                        , artClass = "art-mint"
                        , description =
                            if String.trim model.draft.description == "" then
                                "A neighbor has added this item to the community."

                            else
                                String.trim model.draft.description
                        }
            in
            case result of
                Err message ->
                    ( { model | notice = Just message }, Effect.none )

                Ok listing ->
                    ( { model
                        | addedListings = listing :: model.addedListings
                        , dialog = NoDialog
                        , draft =
                            { title = ""
                            , category = Marketplace.Tools
                            , neighborhood = Marketplace.Maplewood
                            , price = "0"
                            , description = ""
                            }
                        , category = Nothing
                        , neighborhood = Nothing
                        , page = 1
                        , notice = Just "Your item is now listed for this visit."
                      }
                    , Effect.none
                    )


subscriptions : RouteParams -> UrlPath -> Shared.Model -> Model -> Sub Msg
subscriptions routeParams path sharedModel model =
    Sub.none


head : App Data ActionData RouteParams -> List Head.Tag
head _ =
    []


view : App Data ActionData RouteParams -> Shared.Model -> Model -> View (PagesMsg Msg)
view app sharedModel model =
    let
        allListings =
            model.addedListings ++ app.data.listings

        filteredListings =
            Marketplace.filterListings
                { query = model.query
                , category = model.category
                , neighborhood = model.neighborhood
                }
                allListings
                |> sortListings model.sortOrder

        pageSize =
            6

        pageTotal =
            Marketplace.pageCount pageSize (List.length filteredListings)

        visibleListings =
            Marketplace.paginate model.page pageSize filteredListings

        activeListing =
            case model.dialog of
                ListingDetailsDialog listingId ->
                    List.filter (\listing -> Marketplace.listingId listing == listingId) allListings
                        |> List.head

                _ ->
                    Nothing
    in
    { title = "AppaRent — Good things, shared nearby"
    , body =
        [ Html.div [ Attr.class "page-wrap" ]
            [ hero model
            , browseSection model visibleListings (List.length filteredListings) pageTotal
            , Html.section [ Attr.class "community-note" ]
                [ Html.span [ Attr.class "community-note-icon", Attr.attribute "aria-hidden" "true" ] [ Html.text "✳" ]
                , Html.div []
                    [ Html.h2 [] [ Html.text "A little sharing goes a long way." ]
                    , Html.p [] [ Html.text "Borrow what you need. Lend what you love. Get to know the people just around the corner." ]
                    ]
                , Html.button
                    [ Attr.class "button button-light"
                    , Events.onClick (PagesMsg.fromMsg ShowCreateForm)
                    ]
                    [ Html.text "Share an item" ]
                ]
            ]
        , case model.dialog of
            CreateListingDialog ->
                createDialog model

            ListingDetailsDialog _ ->
                activeListing
                    |> Maybe.map listingDialog
                    |> Maybe.withDefault (Html.text "")

            NoDialog ->
                Html.text ""
        , model.notice
            |> Maybe.map noticeView
            |> Maybe.withDefault (Html.text "")
        ]
    }


sortListings : Marketplace.SortOrder -> List Listing -> List Listing
sortListings sortOrder listings =
    case sortOrder of
        Marketplace.Recommended ->
            listings

        Marketplace.PriceAscending ->
            Marketplace.sortByPrice listings


hero : Model -> Html.Html (PagesMsg Msg)
hero model =
    Html.section [ Attr.class "hero" ]
        [ Html.div [ Attr.class "hero-copy" ]
            [ Html.p [ Attr.class "eyebrow" ] [ Html.text "A happier kind of neighborhood" ]
            , Html.h1 [] [ Html.text "Good things,\nshared nearby." ]
            , Html.p [ Attr.class "hero-description" ]
                [ Html.text "The things we need don't have to be things we own. Find what you need from people just around the corner." ]
            , Html.div [ Attr.class "hero-actions" ]
                [ Html.button
                    [ Attr.class "button button-primary"
                    , Events.onClick (PagesMsg.fromMsg ShowCreateForm)
                    ]
                    [ Html.text "Share something" ]
                , Html.a [ Attr.href "#discover", Attr.class "text-link" ] [ Html.text "Explore the neighborhood ↓" ]
                ]
            , Html.div [ Attr.class "hero-proof" ]
                [ Html.div [ Attr.class "avatar-stack", Attr.attribute "aria-hidden" "true" ]
                    [ Html.span [ Attr.class "avatar avatar-one" ] [ Html.text "M" ]
                    , Html.span [ Attr.class "avatar avatar-two" ] [ Html.text "J" ]
                    , Html.span [ Attr.class "avatar avatar-three" ] [ Html.text "P" ]
                    ]
                , Html.p [] [ Html.strong [] [ Html.text "Neighbors helping neighbors" ], Html.br [] [], Html.text "One useful thing at a time" ]
                ]
            ]
        , Html.div [ Attr.class "hero-art", Attr.attribute "aria-hidden" "true" ]
            [ Html.div [ Attr.class "sun-shape" ] []
            , Html.div [ Attr.class "hero-card hero-card-main" ]
                [ Html.div [ Attr.class "hero-card-art art-sand" ] [ Html.text "🛠️" ]
                , Html.p [] [ Html.text "Cordless drill set" ]
                , Html.span [] [ Html.text "Shared with care" ]
                ]
            , Html.div [ Attr.class "hero-card hero-card-note" ]
                [ Html.span [] [ Html.text "✳" ]
                , Html.p [] [ Html.text "Borrow local.\nFeel good." ]
                ]
            , Html.div [ Attr.class "hero-sticker" ] [ Html.text "Good\nneighbors\nmake it." ]
            ]
        ]


browseSection : Model -> List Listing -> Int -> Int -> Html.Html (PagesMsg Msg)
browseSection model listings resultCount pageTotal =
    Html.section [ Attr.id "discover", Attr.class "browse-section" ]
        [ Html.div [ Attr.class "section-heading" ]
            [ Html.div []
                [ Html.p [ Attr.class "eyebrow" ] [ Html.text "The neighborhood shelf" ]
                , Html.h2 [] [ Html.text "Find your next favorite." ]
                , Html.p [ Attr.class "section-subtitle" ] [ Html.text "Useful things, shared by people nearby." ]
                ]
            , Html.label [ Attr.class "neighborhood-filter" ]
                [ Html.span [] [ Html.text "Around" ]
                , Html.select
                    [ Attr.value (Maybe.map Marketplace.neighborhoodName model.neighborhood |> Maybe.withDefault "")
                    , Events.onInput (NeighborhoodSelected >> PagesMsg.fromMsg)
                    , Attr.attribute "aria-label" "Filter by neighborhood"
                    ]
                    (Html.option [ Attr.value "" ] [ Html.text "All neighborhoods" ]
                        :: List.map
                            (\neighborhood ->
                                Html.option
                                    [ Attr.value (Marketplace.neighborhoodName neighborhood) ]
                                    [ Html.text (Marketplace.neighborhoodName neighborhood) ]
                            )
                            Marketplace.neighborhoods
                    )
                ]
            ]
        , Html.div [ Attr.class "browse-toolbar" ]
            [ Html.div [ Attr.class "search-box" ]
                [ Html.span [ Attr.attribute "aria-hidden" "true" ] [ Html.text "⌕" ]
                , Html.input
                    [ Attr.type_ "search"
                    , Attr.placeholder "Search for a drill, tent, mixer..."
                    , Attr.value model.query
                    , Events.onInput (SearchChanged >> PagesMsg.fromMsg)
                    , Attr.attribute "aria-label" "Search items and neighbors"
                    ]
                    []
                , if model.query /= "" then
                    Html.button
                        [ Attr.class "clear-search"
                        , Attr.attribute "aria-label" "Clear search"
                        , Events.onClick (PagesMsg.fromMsg (SearchChanged ""))
                        ]
                        [ Html.text "×" ]

                  else
                    Html.text ""
                ]
            , Html.button
                [ Attr.class "sort-button"
                , Events.onClick (PagesMsg.fromMsg SortByPrice)
                , Attr.attribute "aria-pressed"
                    (case model.sortOrder of
                        Marketplace.Recommended ->
                            "false"

                        Marketplace.PriceAscending ->
                            "true"
                    )
                ]
                [ Html.span [ Attr.attribute "aria-hidden" "true" ] [ Html.text "↕" ]
                , Html.text
                    (case model.sortOrder of
                        Marketplace.Recommended ->
                            "Sort: recommended"

                        Marketplace.PriceAscending ->
                            "Price: low to high"
                    )
                ]
            ]
        , Html.div [ Attr.class "category-list", Attr.attribute "role" "group", Attr.attribute "aria-label" "Filter by category" ]
            (List.map (categoryButton model.category) (Nothing :: List.map Just Marketplace.categories))
        , Html.div [ Attr.class "results-bar" ]
            [ Html.p []
                [ Html.strong [] [ Html.text (String.fromInt resultCount) ]
                , Html.text
                    (if resultCount == 1 then
                        " good thing nearby"

                     else
                        " good things nearby"
                    )
                ]
            , Html.button
                [ Attr.class "share-inline"
                , Events.onClick (PagesMsg.fromMsg ShowCreateForm)
                ]
                [ Html.text "+ Share an item" ]
            ]
        , if List.isEmpty listings then
            Html.div [ Attr.class "empty-state" ]
                [ Html.span [ Attr.attribute "aria-hidden" "true" ] [ Html.text "⌕" ]
                , Html.h3 [] [ Html.text "Nothing on this shelf just yet." ]
                , Html.p [] [ Html.text "Try another search or clear a filter to see more neighborly finds." ]
                , Html.button
                    [ Attr.class "button button-secondary"
                    , Events.onClick (PagesMsg.fromMsg (SearchChanged ""))
                    ]
                    [ Html.text "Clear search" ]
                ]

          else
            Html.div [ Attr.class "listing-grid" ] (List.map listingCard listings)
        , if pageTotal > 1 then
            pagination model.page pageTotal

          else
            Html.text ""
        ]


categoryButton : Maybe Marketplace.Category -> Maybe Marketplace.Category -> Html.Html (PagesMsg Msg)
categoryButton activeCategory category =
    let
        label =
            category
                |> Maybe.map Marketplace.categoryName
                |> Maybe.withDefault "Everything"

        isActive =
            activeCategory == category
    in
    Html.button
        [ Attr.class
            (if isActive then
                "category-chip is-active"

             else
                "category-chip"
            )
        , Events.onClick (PagesMsg.fromMsg (CategorySelected category))
        , Attr.attribute "aria-pressed"
            (if isActive then
                "true"

             else
                "false"
            )
        ]
        [ Html.text label ]


listingCard : Listing -> Html.Html (PagesMsg Msg)
listingCard listing =
    Html.article [ Attr.class "listing-card" ]
        [ Html.button
            [ Attr.class ("listing-art " ++ Marketplace.listingArtClass listing)
            , Events.onClick (PagesMsg.fromMsg (OpenListing (Marketplace.listingId listing)))
            , Attr.attribute "aria-label" ("View " ++ Marketplace.listingTitle listing)
            ]
            [ Html.span [ Attr.class "listing-emoji", Attr.attribute "aria-hidden" "true" ] [ Html.text (Marketplace.listingEmoji listing) ]
            , Html.span [ Attr.class "listing-category" ] [ Html.text (Marketplace.categoryName (Marketplace.listingCategory listing)) ]
            ]
        , Html.div [ Attr.class "listing-info" ]
            [ Html.div [ Attr.class "listing-title-row" ]
                [ Html.h3 [] [ Html.text (Marketplace.listingTitle listing) ]
                , Html.span [ Attr.class "listing-price" ] [ Html.text (Marketplace.priceLabel (Marketplace.listingPrice listing)) ]
                ]
            , Html.p [ Attr.class "listing-location" ]
                [ Html.span [ Attr.attribute "aria-hidden" "true" ] [ Html.text "⌖" ]
                , Html.text (Marketplace.neighborhoodName (Marketplace.listingNeighborhood listing) ++ " · shared by " ++ Marketplace.listingOwner listing)
                ]
            , Html.button
                [ Attr.class "card-link"
                , Events.onClick (PagesMsg.fromMsg (OpenListing (Marketplace.listingId listing)))
                ]
                [ Html.text "Take a closer look ↗" ]
            ]
        ]


pagination : Int -> Int -> Html.Html (PagesMsg Msg)
pagination current total =
    Html.nav [ Attr.class "pagination", Attr.attribute "aria-label" "Listing pages" ]
        [ Html.button
            [ Attr.class "page-button"
            , Attr.disabled (current <= 1)
            , Events.onClick (PagesMsg.fromMsg (PageSelected (current - 1)))
            ]
            [ Html.text "← Previous" ]
        , Html.span [] [ Html.text ("Page " ++ String.fromInt current ++ " of " ++ String.fromInt total) ]
        , Html.button
            [ Attr.class "page-button"
            , Attr.disabled (current >= total)
            , Events.onClick (PagesMsg.fromMsg (PageSelected (current + 1)))
            ]
            [ Html.text "Next →" ]
        ]


createDialog : Model -> Html.Html (PagesMsg Msg)
createDialog model =
    Html.div [ Attr.class "dialog-backdrop", Attr.attribute "role" "presentation" ]
        [ Html.section [ Attr.class "dialog", Attr.attribute "role" "dialog", Attr.attribute "aria-modal" "true", Attr.attribute "aria-labelledby" "create-title" ]
            [ Html.div [ Attr.class "dialog-heading" ]
                [ Html.div []
                    [ Html.p [ Attr.class "eyebrow" ] [ Html.text "Pass the good along" ]
                    , Html.h2 [ Attr.id "create-title" ] [ Html.text "Share something useful." ]
                    ]
                , closeButton HideCreateForm
                ]
            , Html.p [ Attr.class "dialog-intro" ] [ Html.text "Add an item to the neighborhood shelf. This prototype keeps new listings in this page only." ]
            , Html.label [ Attr.class "field-label" ]
                [ Html.text "Item name"
                , Html.input
                    [ Attr.value model.draft.title
                    , Attr.placeholder "e.g. Cordless drill set"
                    , Events.onInput (TitleChanged >> PagesMsg.fromMsg)
                    ]
                    []
                ]
            , Html.div [ Attr.class "field-row" ]
                [ Html.label [ Attr.class "field-label" ]
                    [ Html.text "Category"
                    , Html.select
                        [ Attr.value (Marketplace.categoryName model.draft.category)
                        , Events.onInput (CategoryDraftChanged >> PagesMsg.fromMsg)
                        ]
                        (List.map
                            (\category ->
                                Html.option
                                    [ Attr.value (Marketplace.categoryName category) ]
                                    [ Html.text (Marketplace.categoryName category) ]
                            )
                            Marketplace.categories
                        )
                    ]
                , Html.label [ Attr.class "field-label" ]
                    [ Html.text "Neighborhood"
                    , Html.select
                        [ Attr.value (Marketplace.neighborhoodName model.draft.neighborhood)
                        , Events.onInput (NeighborhoodDraftChanged >> PagesMsg.fromMsg)
                        ]
                        (List.map
                            (\neighborhood ->
                                Html.option
                                    [ Attr.value (Marketplace.neighborhoodName neighborhood) ]
                                    [ Html.text (Marketplace.neighborhoodName neighborhood) ]
                            )
                            Marketplace.neighborhoods
                        )
                    ]
                ]
            , Html.label [ Attr.class "field-label" ]
                [ Html.text "Daily price (use 0 for free)"
                , Html.div [ Attr.class "price-input" ]
                    [ Html.span [] [ Html.text "$" ]
                    , Html.input
                        [ Attr.type_ "number"
                        , Attr.min "0"
                        , Attr.step "0.01"
                        , Attr.value model.draft.price
                        , Events.onInput (PriceChanged >> PagesMsg.fromMsg)
                        ]
                        []
                    , Html.span [] [ Html.text "per day" ]
                    ]
                ]
            , Html.label [ Attr.class "field-label" ]
                [ Html.text "A few details (optional)"
                , Html.textarea
                    [ Attr.value model.draft.description
                    , Attr.placeholder "What should a neighbor know before borrowing it?"
                    , Attr.rows 3
                    , Events.onInput (DescriptionChanged >> PagesMsg.fromMsg)
                    ]
                    []
                ]
            , Html.div [ Attr.class "dialog-actions" ]
                [ Html.button [ Attr.class "button button-secondary", Events.onClick (PagesMsg.fromMsg HideCreateForm) ] [ Html.text "Maybe later" ]
                , Html.button [ Attr.class "button button-primary", Events.onClick (PagesMsg.fromMsg CreateListing) ] [ Html.text "Add to the shelf" ]
                ]
            ]
        ]


listingDialog : Listing -> Html.Html (PagesMsg Msg)
listingDialog listing =
    Html.div [ Attr.class "dialog-backdrop", Attr.attribute "role" "presentation" ]
        [ Html.section [ Attr.class "dialog detail-dialog", Attr.attribute "role" "dialog", Attr.attribute "aria-modal" "true", Attr.attribute "aria-labelledby" "detail-title" ]
            [ Html.div [ Attr.class ("detail-art " ++ Marketplace.listingArtClass listing) ]
                [ Html.span [ Attr.attribute "aria-hidden" "true" ] [ Html.text (Marketplace.listingEmoji listing) ]
                , closeButton CloseListing
                ]
            , Html.p [ Attr.class "eyebrow" ] [ Html.text (Marketplace.categoryName (Marketplace.listingCategory listing)) ]
            , Html.h2 [ Attr.id "detail-title" ] [ Html.text (Marketplace.listingTitle listing) ]
            , Html.p [ Attr.class "listing-location" ] [ Html.text (Marketplace.neighborhoodName (Marketplace.listingNeighborhood listing) ++ " · shared by " ++ Marketplace.listingOwner listing) ]
            , Html.p [ Attr.class "detail-description" ] [ Html.text (Marketplace.listingDescription listing) ]
            , Html.div [ Attr.class "detail-footer" ]
                [ Html.span [ Attr.class "detail-price" ] [ Html.text (Marketplace.priceLabel (Marketplace.listingPrice listing)) ]
                , Html.button [ Attr.class "button button-primary", Events.onClick (PagesMsg.fromMsg ContactOwner) ] [ Html.text "Contact neighbor" ]
                ]
            ]
        ]


closeButton : Msg -> Html.Html (PagesMsg Msg)
closeButton msg =
    Html.button
        [ Attr.class "close-button"
        , Attr.attribute "aria-label" "Close dialog"
        , Events.onClick (PagesMsg.fromMsg msg)
        ]
        [ Html.text "×" ]


noticeView : String -> Html.Html (PagesMsg Msg)
noticeView message =
    Html.div [ Attr.class "notice", Attr.attribute "role" "status" ]
        [ Html.p [] [ Html.text message ]
        , Html.button
            [ Attr.class "notice-close"
            , Attr.attribute "aria-label" "Dismiss message"
            , Events.onClick (PagesMsg.fromMsg DismissNotice)
            ]
            [ Html.text "×" ]
        ]
