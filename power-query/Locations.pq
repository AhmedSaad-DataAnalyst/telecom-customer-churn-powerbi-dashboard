// RawFolder parameter = "D:\\claude life\\01_Projects\\04_Telecom_Churn\\01_Raw_Data\\"
let
    Source = Csv.Document(File.Contents(RawFolder & "telecom_customer_churn.csv"), [Delimiter = ",", Columns = 38, Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
    Kept = Table.SelectColumns(Promoted, {"Zip Code", "City", "Latitude", "Longitude"}),
    Typed = Table.TransformColumnTypes(Kept, {{"Zip Code", type text}, {"City", type text}, {"Latitude", type number}, {"Longitude", type number}}, "en-US"),
    Grouped = Table.Group(Typed, {"Zip Code"}, {{"City", each List.First([City]), type text}, {"Latitude", each List.Average([Latitude]), type number}, {"Longitude", each List.Average([Longitude]), type number}}),
    PopSource = Csv.Document(File.Contents(RawFolder & "telecom_zipcode_population.csv"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    PopPromoted = Table.PromoteHeaders(PopSource, [PromoteAllScalars = true]),
    PopTyped = Table.TransformColumnTypes(PopPromoted, {{"Zip Code", type text}, {"Population", Int64.Type}}),
    Joined = Table.NestedJoin(Grouped, {"Zip Code"}, PopTyped, {"Zip Code"}, "Pop", JoinKind.LeftOuter),
    Expanded = Table.ExpandTableColumn(Joined, "Pop", {"Population"}, {"Population"}),
    AddState = Table.AddColumn(Expanded, "State", each "California", type text),
    Final = Table.TransformColumnTypes(AddState, {{"Population", Int64.Type}})
in
    Final
