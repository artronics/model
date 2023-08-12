import {useEffect, useState} from 'react'
import './App.css'
import {invoke} from '@tauri-apps/api';

function App() {
    const [count, setCount] = useState(0)
    useEffect(() => {
        invoke('greet', {name: 'World'})
            // `invoke` returns a Promise
            .then((response) => console.log(response))
    }, []);

    return (
        <>
            <div>helloy</div>
        </>
    )
}

export default App
