function TabBar() {
    const item = (t: string, i: number) => (<li key={i} className="inline-block p-2">{t}</li>)
    const items = ["Files", "Classes"]

    return (
        <ol className="border-b-[1px] border-gray-800 px-2 ">
            {items.map(item)}
        </ol>
    )
}

function SearchInput() {
    return (
        <div className="flex flex-row p-2">
            <i className="fa fa-search px-2 mt-[2px]"></i>
            <input className="grow pl-2 bg-stone-600"/>
        </div>
    )
}

interface SearchResult {
    icon: string,
    text: string
}

function Results(props: { items: SearchResult[] }) {
    const item = (r: SearchResult, i: number) => (<li key={i}><i className={`fa fa-${r.icon} pr-2`}/>{r.text}</li>)
    return (
        <div className="px-4">
            <ol>
                {props.items.map(item)}
            </ol>
        </div>
    )
}

function PopupFooter() {
    return (
        <div className="border-t-[1px] border-gray-800 px-4">information in the footer</div>
    )
}

function SearchPopup() {
    return (
        <>
            <div className="bg-stone-600 w-full rounded-md">
                <TabBar/>
                <SearchInput/>
                <Results items={[{text: "foo", icon: "camera"}, {text: "bar", icon: "camera"}]}/>
                <PopupFooter/>
            </div>
        </>
    )
}

export default SearchPopup