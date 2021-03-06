#
# This is the server logic of a Shiny web application. You can run the
# application by clicking 'Run App' above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

library(shiny)
library(knitr)

# Allows us to add emojis to ggplot

library(emojifont)

# For the wordcloud page

library(wordcloud2)

# Prettifies ggplot scales

library(scales)

# This allows us to create network graphs

library(igraph)
library(networkD3)
library(ggimage)

# Ggplot themes

library(ggthemr)
library(tidyverse)

# Reading in the emoji data

emoji_data <- read_csv("data-cleaned.csv",
                       col_types = cols(
                           time = col_character(),
                           confirm = col_character(),
                           all_emojis = col_character(),
                           year = col_double(),
                           gender = col_character(),
                           house = col_character(),
                           ethnicity = col_character(),
                           residence = col_character(),
                           concentration = col_character(),
                           secondary = col_character(),
                           email = col_character()
                       ))

# Pivoting table wider so that there is one column for each emoji
# We split by commas and remove unnecessary symbols

emoji_data$all_emojis <- str_split(emoji_data$all_emojis, ",")
emoji_data$all_emojis <- gsub("[^[:alnum:]_,]", "", emoji_data$all_emojis)
emoji_data$all_emojis <- sub(".", "", emoji_data$all_emojis)

emoji_data_separated <- emoji_data %>%
    separate(all_emojis, c("first", "second", "third", "fourth", 
                           "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"), 
             sep=",", extra="drop")

# Pivoting longer to create table with emoji use and order

emoji_data_longer <- emoji_data_separated %>%
    pivot_longer(names_to = "position", 
                 values_to = "emoji_name",
                 cols = c("first", "second", "third", "fourth", "fifth", "sixth", 
                          "seventh", "eighth", "ninth", "tenth"))

# Create summary of use of all emojis by position

emoji_summarized <- emoji_data_longer %>%
    group_by(position, emoji_name) %>%
    summarize(count = n()) %>%
    arrange(emoji_name) %>%
    filter(count > 1)

# Here we take only the summary of all emojis, regardless of position

emoji_data_total <- emoji_data_longer %>%
    group_by(emoji_name) %>%
    summarize(count = n())

# Prettifying the names of emojis

emoji_data_total$emoji_name <- gsub("_", " ", emoji_data_total$emoji_name)

# Making a copy of the previous data and prettifying the names
# for an additional graph

emoji_data_specifics <- emoji_data_longer

emoji_data_specifics$emoji_name <- gsub("_", " ", emoji_data_specifics$emoji_name)

# Information for emoji connections

emoji_data_connections <- emoji_data_separated %>%
    select("first", "second", "third", "fourth", "fifth", "sixth", "seventh", 
           "eighth", "ninth", "tenth")

# We create edges between each users' emojis

emoji_data_connections_graph <- graph.data.frame(emoji_data_connections, directed = FALSE)

# Remove duplicate edges

emoji_data_connections_graph <- simplify(emoji_data_connections_graph)

# Find group membership

wt <- cluster_walktrap(emoji_data_connections_graph, steps = 6)
members <- membership(wt)

# Convert igraph to list for networkD3

converted <- igraph_to_networkD3(emoji_data_connections_graph, group = members)

# Creating the heart plot

heart_plot <- emoji_data_longer %>%
    filter(grepl('heart', emoji_name, fixed = TRUE)) %>%
    group_by(emoji_name, position, gender, year) %>%
    summarize(count = n())

# Releveling

heart_plot$position <- factor(heart_plot$position, 
                              levels = c("first","second","third", "fourth", 
                                         "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"))
                              
# Getting only emoji faces data

faces_plot <- emoji_data_longer %>%
    filter(grepl('face', emoji_name, fixed = TRUE))

# Define server logic 

shinyServer(function(input, output) {
    
    # Rendering homepage
    
    output$aboutText <- renderUI({
        HTML(markdown::markdownToHTML(knit('about-text.Rmd', quiet = TRUE)))
    })
    
    # Rendering the author page
    
    output$aboutAuthor <- renderUI({
        HTML(markdown::markdownToHTML(knit('about-author.Rmd', quiet = TRUE)))
    })
    
    # Rendering the wordcloud
    
    output$wordcloud2 <- renderWordcloud2({
        wordcloud2(data = emoji_data_total, 
                   fontFamily = "sans-serif", 
                   color = rep_len(c("salmon","lightpink", "lightblue", "orange"), 
                                  nrow(emoji_data_total)))
    })
    
    # Creating a reactive function for the heart graph,
    # depending on the user selecting filter
    
    newHeartGroup <- reactive({
        heart_plot %>%
            group_by(emoji_name) %>%
            group_by_at(input$heartgrouping, .add = TRUE) %>%
            summarize(count = n())
    })
    
    # Rendering the heart plot, with emojis for each bar on the ggplot
    
    output$heartPlot <- renderPlot({
        ggthemr_reset()
        ggplot(newHeartGroup(),
            aes(x = reorder(emoji_name, count), y = count)) + 
            geom_col(position = position_dodge2(width = 10, preserve = "single"),
                     aes_string(fill = input$heartgrouping)) +
            geom_emoji(aes(image = case_when(emoji_name == 'sparkling_heart' ~ '1f496',
                                             emoji_name == 'red_heart' ~ '2764',
                                             emoji_name == 'beating_heart' ~ '1f493',
                                             emoji_name == 'yellow_heart' ~ '1f49b',
                                             emoji_name == 'purple_heart' ~ '1f49c',
                                             emoji_name == 'heart_with_arrow' ~ '1f498',
                                             emoji_name == 'heavy_heart_exclamation' ~ '1f495',
                                             emoji_name == 'revolving_hearts' ~ '1f49e',
                                             emoji_name == 'smiling_cat_face_with_hearteyes' ~ '1f63b',
                                             emoji_name == 'smiling_face_with_3_hearts' ~ '263a',
                                             emoji_name == 'smiling_face_with_hearteyes' ~ '1f60d',
                                             emoji_name == 'two_hearts' ~ '1f495',)),
                       position = position_dodge2(width = 1, preserve = "single"),
                       size = 0.01) +
            
            # Adding labels and changing the theme to enable more color use
            
            labs(title = "Heart Frequency in Commonly Used Emojis",
                 x = "emoji name") + 
            coord_flip() +
            theme_bw()
    })
    
    # Rendering emoji use by year
    
    output$emojiByYear <- renderPlot(({
        ggthemr('dust')
        faces_plot %>%
            
            # Getting summary of faces only
            
            group_by(emoji_name, year) %>%
            summarize(count = n()) %>%
            
            # Getting total count of faces by year
            
            nest() %>%
            mutate(total_count = map(data, ~sum(.$count))) %>%
            unnest(cols = c(data, total_count)) %>%
            
            # Only showing the most relevant faces
            
            filter(total_count > 4) %>%
            
            # Creating percentages by class
            
            mutate(fraction = case_when(year == 2020 ~ count / 18,
                                        year == 2021 ~ count / 8,
                                        year == 2022 ~ count / 8,
                                        year == 2023 ~ count / 11
            )) %>%
            
            # GGplotting faces
            
            ggplot(aes(x = reorder(emoji_name, fraction), y = fraction)) + 
            geom_col(position = position_dodge2(width = 1, preserve = "single")) +
            coord_flip() +
            labs(title = "Most Frequently Used Faces",
                 subtitle = "Grouped by graduation year",
                 x = "emoji name") +
            facet_wrap(~year)
    }))
    
    # Rendering emoji use by top houses (previously found by sorting by
    # top count of houses)
    
    output$emojiByHouse <- renderPlot({
        ggthemr('dust')
        faces_plot %>%
            
            # Similar code as the faces plot; grouping and nesting in order
            # to get total count by house before unnesting and graphing
            
            group_by(emoji_name, house) %>%
            summarize(count = n()) %>%
            filter(house == "Winthrop" | house == "Adams" | 
                       house == "Freshman Housing" | house == "Eliot") %>%
            nest() %>%
            mutate(total_count = map(data, ~sum(.$count))) %>%
            unnest(cols = c(data, total_count)) %>%
            filter(total_count > 4) %>%
            mutate(fraction = case_when(house == "Winthrop" ~ count / 12,
                                        house == "Freshman Housing" ~ count / 11,
                                        house == "Eliot" ~ count / 7,
                                        house == "Adams" ~ count / 4
            )) %>%
            
            # Creating plot
            
            ggplot(aes(x = reorder(emoji_name, fraction), y = fraction)) + 
            geom_col(position = position_dodge2(width = 1, preserve = "single")) +
            coord_flip() +
            labs(title = "Most Frequently Used Faces",
                 subtitle = "Grouped by top houses of respondents",
                 x = "emoji name") +
            facet_wrap(~house)
    })
    
    # Rendering top emoji use by top states
    
    output$emojiByState <- renderPlot({
        ggthemr('dust')
        faces_plot %>%
            
            # Similar code as the faces plot; grouping and nesting in order
            # to get total count by state before unnesting and graphing
            
            group_by(emoji_name, residence) %>%
            summarize(count = n()) %>%
            filter(residence == "California" | residence == "New York" | 
                       residence == "Massachusetts" | residence == "Texas") %>%
            nest() %>%
            mutate(total_count = map(data, ~sum(.$count))) %>%
            unnest(cols = c(data, total_count)) %>%
            filter(total_count > 4) %>%
            mutate(fraction = case_when(residence == "California" ~ count / 10,
                                        residence == "New York" ~ count / 8,
                                        residence == "Massachusetts" ~ count / 5,
                                        residence == "Texas" ~ count / 4
            )) %>%
            
            # Creating plot
            
            ggplot(aes(x = reorder(emoji_name, fraction), y = fraction)) + 
            geom_col(position = position_dodge2(width = 1, preserve = "single")) +
            coord_flip() +
            labs(title = "Most Frequently Used Faces",
                 subtitle = "Grouped by top states of respondents",
                 x = "emoji name") +
            facet_wrap(~residence)})
    
    # Rendering top emoji use by gender
    
    output$emojiByGender <- renderPlot({
        ggthemr('dust')
        faces_plot %>%
            
            # Similar code as the faces plot; grouping and nesting in order
            # to get total count by gender before unnesting and graphing
            
            group_by(emoji_name, gender) %>%
            summarize(count = n()) %>%
            nest() %>%
            mutate(total_count = map(data, ~sum(.$count))) %>%
            unnest(cols = c(data, total_count)) %>%
            filter(total_count > 4) %>%
            mutate(fraction = case_when(gender == "Female" ~ count / 31,
                                        gender == "Male" ~ count / 14)) %>%
            
            # Creating plot
            
            ggplot(aes(x = reorder(emoji_name, fraction), y = fraction)) + 
            geom_col(position = position_dodge2(width = 1, preserve = "single")) +
            coord_flip() +
            labs(title = "Most Frequently Used Faces by Gender",
                 subtitle = "Grouped by gender of respondents",
                 x = "emoji name") +
            facet_wrap(~gender)
    })
    
    # Adding a modal whenever an emoji is selecting on the wordcloud
    
    observeEvent(input$selectedWord, {
        
        # Cleaning the name of the emoji
        
        cleanedInput <- gsub(":.*","",isolate(input$selectedWord))
        
        # Setting the UI inside the modal
        
        showModal(modalDialog(
            title = "Emoji-specific Information",
            tags$img(
                src = base64enc::dataURI(file = paste0("./emoji-imgs/", cleanedInput, ".png"),
                                         mime = "image/png"),
                height = "50px",
                align = "center"),
            renderText(cleanedInput),
            
            # Rendering plot depending on user input
            
            selectInput("demographic", "", c("gender", "year", "concentration", "residence")),
            renderPlot({
                ggthemr('dust')
                demographic <- input$demographic

                ggplot(emoji_data_specifics %>%
                            filter(emoji_name == cleanedInput), aes_string(demographic)) +
                    geom_bar() +
                    theme_classic() +
                    scale_y_continuous(breaks = pretty_breaks()) + 
                    coord_flip()
                    
            }),
            easyClose = TRUE,
            footer = NULL
        ))
    })
    
    # Rendering network
    
    output$network <- renderForceNetwork(

        forceNetwork(Links = converted$links, Nodes = converted$nodes, Source = 'source',
                     Target = 'target', NodeID = 'name', Group = 'group',
                     zoom = TRUE, linkDistance = 200)
    )

})
