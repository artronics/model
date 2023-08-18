function TabBar() {
    const item = (t: string) => (<li className="inline-block p-2">{t}</li>)
    const items = [item("Files"), item("Classes")]

    return (
        <ol className="border-b-[1px] border-gray-800 px-2 ">
            {items}
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
    const item = (i: SearchResult) => (<li className="bg-red-100"><i className={`fa fa-${i.icon} pr-2`}/>{i.text}</li>)
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